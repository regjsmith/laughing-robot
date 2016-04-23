# Reg Smith - reg.smith@uk.bp.com
# April 2012
# Process TFS migration tool logfile to enable application of clearcase labels to equivalent changeset version in TFS after migration
# Have a look at the end of the script to see a basic description of the format of the logfile and how it gets processed. 
# Assumes you are only dealing with one filter pair and maybe one cloaked filter but should work if multiple active
# filter pairs were specified when the migration tool was run.

# Cmd line options
use Getopt::Long;
usage() if (!GetOptions('help|?'        => \$help,
                        'log=s'         => \$log, 
                        'collection=s'  => \$collection, 
                        'labelcmd'      => \$labelcmd,
                        'map'           => \$map,
                        'ccrootpath=s'  => \$opt_ccrootpath,
                        'tfsrootpath=s' => \$opt_tfsrootpath, 
						'verbose'       => \$verbose
                       ) 
                       or defined $help
           );
		   
if(!$log)
{
        print "\n";
        print "You must specify at least the migration logfile to process using -log and one of -map or -labelcmd \n";
        print "(-labelcmd also requires -collection)\n";
        usage();
}
if(!$map && !$labelcmd)
{
        print "\n";
        print "You must specify either -map or -labelcmd (-labelcmd also requires -collection)\n";
        usage();
}
if($labelcmd && !$collection)
{
        print "\n";
        print "You must specify -collection if you specified -labelcmd \n";
        usage();
}
# Open the migration logfile and read line by line. I did try reading entire file into string to make matching over multi-line comments easier
# but caused more headaches with lines being matched but losing order in which they were matched so reverted to reading in a line at a time
# (which would also avoid any potential memory issues if reading very large log files).
open(FILE, $log) or die "Cannot open log file $log\n";

while(<FILE>)
{
    # Report start of session, can be multiple sessions in one log file
    if(/StartSessionGroup: Enter with sessionGroupUniqueId: (.*?)$/)
    {
        $sessionNum++;
        $SessionUniqueID=$1;
        $SessionUniqueID =~ s/\s+$//; # trim trailing space
        $SessionUniqueID{$sessionNum}=$SessionUniqueID;
  
        print "REM *** Start of session number $sessionNum detected (UniqueID $SessionUniqueID)\n" if $verbose;
    }
    
    # Report end of this session
    if(/Migration is done/)
    {
        print "REM *** End of session number $sessionNum detected (UniqueID $SessionUniqueID)\n\n" if $verbose;
    }
    
	# Pick out TFS root path from filter pair unless overidden with -tfsrootpath option
	if(!$opt_tfsrootpath)
	{
		if(/Added TFS workspace mapping from server path \'(.*?)\' to local path/)
		{
			# Index of this tfs path pair - how many have we seen so far?
            $tfsrootpathindex++;
            $tfsrootpath=$1;
            $TFSRootPaths{$tfsrootpathindex}=$tfsrootpath;
            $tfsrootpathindex2sessionNum{$tfsrootpathindex}=$sessionNum;
			print "REM tfsrootpath from TFS workspace mapping pair (mapping pair number $tfsrootpathindex) = $tfsrootpath\n" if $verbose;
		}
	}
	else # -tfsroot option given 
	{
		$tfsrootpath=$opt_tfsrootpath;
        # Index of this tfs path pair - how many have we seen so far?
        $tfsrootpathindex++;
        $TFSRootPaths{$tfsrootpathindex}=$tfsrootpath;
        $tfsrootpathindex2sessionNum{$tfsrootpathindex}=$sessionNum;
	}
	
	# Report any cloaked filter if -verbose option given
	if(/Added TFS workspace cloak of server path \'(.*?)$/)
	{
		$tfscloakpath=$1;
		print "REM Cloaked path $tfscloakpath\n" if $verbose;
	}
    	
    # Pick out clearcase root path from filter pair unless overidden with -ccrootpath option
	if(!$opt_ccrootpath)
	{
		if(/ClearCase history command\: .*? -pname \'(.*?)\'\'/)
		{
			$ccrootpath=$1;
            
			# Index of this CC path pair - how many have we seen so far?
            $ccrootpathindex++;
            $ccrootpath=$1;
            $CCRootPaths{$ccrootpathindex}=$ccrootpath;  
            $ccrootpathindex2sessionNum{$ccrootpathindex}=$sessionNum;            
			print "REM ccrootpath from ClearCase history command   (mapping pair number $ccrootpathindex) = $ccrootpath\n" if $verbose;
		}
	}
	else
	{
		$ccrootpath=$opt_ccrootpath;
        $ccrootpathindex++;
        $CCRootPaths{$ccrootpathindex}=$ccrootpath;
        $ccrootpathindex2sessionNum{$ccrootpathindex}=$sessionNum;
	}	
	
	# Read blocks of the TFS Migration tool logfile that are essentially the parsed output from the cleartool lshistory command. The bits we
	# are interest in from this are the changeID (actually the clearcae eventID from the vob database), labels (if any) and the filename (we
	# don't actually require the clearcase version part of the path, we only really need the filename and changeset to apply a label in TFS)
	# but keep a note of the clearcase version for warings and verbose output if -verbose option was given.

	if(/TfsMigrationShell.exe\ Information\:\ 0\ \:\ VersionControl\:\ \|\| # Fixed starting literal keywords..our cue it's a version 
		(\d+)                                                               # ChangeID (event id from vob db)
		\s\|                                                                # space and "|" delimiter
		\ Checkin\ \|\ version\ \|                                          # Literal keywords "Checkin | Version"
		/x)
	{
		my $ChangeID=$1;
		
		# Output from lsh can span over multiple lines if cc checkin comments also spanned mulitple lines so want to
		# aggregate all the lines together into one string before matching comments, labels, filename and cc version
		# Looking for the @@ in filename which is clearcase file@@version delimiter, we want to get all lines including
		# this one (if it is not all on one line.

		#my $lsh_output=$_;
		#until($lsh_output =~ /@@/)
		#{
		#	my $nextline = <FILE>;
		#	$lsh_output = $lsh_output . $nextline;
		#}
		
		# Same as above block but more succint (obfuscated?!), leaving it in to help claify.
		until(/@@/)
		{
			$_ .= <FILE>;
		}

		#if($lsh_output =~ /([^|]*?)                       # comment (if present may contain newline(s))
		if(/([^|]*?)                                       # comment (if present may contain newline(s))
	         \|\s
	         \d{2}\/\d{2}\/\d{4} \s \d{2}\:\d{2}\:\d{2}    # date+time stamp
	         \s\|
	         \s([^|]*?)                                    # label(s) - will be in comma separated list if more than one  
	         \s\|
	         \s([^\@]+?) \@\@(.*$)                         # Filename, without clearcase version part (i.e everything from the @@ chopped off)
	         /sx)                                          # x to embed comments above in regex
		{
			# Assign to more meaningful variables the matches for comment,labels,filename, clearcase version
			my $comment=$1;
			my $Labels=$2;
			my $File=$3;
			
			# Even though we are not using the clearcase branch/version still keep a note of it for reporting if -verbose option used
			my $ccversionpath=$4; 
			$ccversionpath =~ s/\s+$//; # strip off trailing whitespace for tidier reporting -verbose option used
			
			# Record filename, labels and root paths for changeID in hash keyed off the changeID
			$ID2File{$ChangeID}=$File;
			$ID2CCVerPath{$ChangeID}=$ccversionpath;
			$ID2Labels{$ChangeID}=$Labels;
			$ID2CCRootPath{$ChangeID}=$CCRootPaths{$ccrootpathindex};
			$ID2TFSRootPath{$ChangeID}=$TFSRootPaths{$ccrootpathindex}; # We want the same index as the ccroot for tfsroot
			$ID2CCComment{$ChangeID}=$comment;
		}
	}
	
	# Keep a record of any cloaked files, they are reported as being skipped
	if(/Skipping history record because the path \'(.*?)\' is not mapped in a filter string/)
	{
		my $cloakedFile=$1;
		
		# Use hash to keep record if we have seen this cloaked file
		$cloakedFiles{$cloakedFile}++ ;
		print "REM Skipping cloaked file $cloakedFile \n" if $verbose;
	}	
	
    # Read the 4-line blocks of the logfile that contain the TFS checkin and changeset information. The ChangeId here is actually the lowest
    # ID that is in the the changeset, a sort of "low water mark" value - if your ID for a particular file from the parsing above is equal
    # or greater to a particular changeset, but less than the next changeset low water mark then it goes in this changeset.

    if(/VersionControl: Processing ChangeGroup #(\d+), change (\d+)/)
    {
        my $ChangeGroup=$1 ;
        my $changeID_LWM=$2 ;
		
		# Want to aggregate the 4 line blocks into single string
		my $lsh_output=$_;
		until($lsh_output =~ /VersionControl: Checked in change (\d+)/)
		{
			my $nextline = <FILE>;
			$lsh_output = $lsh_output . $nextline;
		}
		my $ChangeSet=$1;
        
        # Record Changeset's ID low water mark value
        $LWM2CS{$changeID_LWM}=$ChangeSet;
    }
}

# Print out path pairs
if($verbose)
{           
    # Loop through path pair strings to get max path lengths for neat aligned output
    foreach my $index (1 .. $ccrootpathindex)
    {
        my $CCPairThisInx=$CCRootPaths{$index};
        my $LengthCCPath=length($CCPairThisInx);
        
        # Sort to get longest pathlength
        if($LengthCCPath > $PrevLengthCCPath)  {$MaxLengthCCPath = $LengthCCPath;}
        
        $PrevLengthCCPath=$LengthCCPath;  
    }
    
    # Header
    $CCHeaderPadLength=$MaxLengthCCPath - length("Clearcase path") + 4;
    print "\n";
    print "REM Path mapping pairs\n";
    print "REM Session    Clearcase path" . " "x $CCHeaderPadLength . "TFS path\n";
    
    # Loop through path pairs again but this time print them
    foreach my $index (1 .. $ccrootpathindex)
    {
        my $CCPairThisInx=$CCRootPaths{$index};
        my $TFSPairThisInx=$TFSRootPaths{$index};
        my $sessionNum=$ccrootpathindex2sessionNum{$index};
        
        $CCPadLength=$MaxLengthCCPath  - length($CCPairThisInx)  +4;
        
        # Pad out
        $CCPairThisInxPadded=$CCPairThisInx . " "x$CCPadLength;
        
        print "REM $sessionNum          $CCPairThisInxPadded$TFSPairThisInx\n";
    }
}
# Loop through all the changeID's, check which changeset they fall under and print out  
# "File | Changeset | Label" if -map option was given or tfs labelling command if -labelcmd option was given.
ID:foreach my $ID (sort keys %ID2File) 
{ 
    LWM:foreach my $LWM (sort keys %LWM2CS) 
    {       
        # Exact match, ID is equal to low water mark
		if ($ID == $LWM) 
        {       
           # Go and print some output
		   printRecord($ID,$LWM);
           
           # Make a note we have now seen/dealt with this ID (couldn't seem to stop drop through case happenning otherwise)
           $seen{$ID}++;
           
           # Go straight to grab the next ID, we are done with this one
           next ID;
        }               
        
        # Keep fetching the next LWM values till our ID value is no longer bigger then we know it belongs in the previous LWM (ID is in the band of  
		# values greater or equalto the previous low water mark but less than value for next higher low water mark)
        if ($ID > $LWM)
        {
           $PrevLWM=$LWM;
           next LWM;
        }

        printRecord($ID,$PrevLWM);
        
        # Make a note we have now seen/dealt with this ID - couldn't seem to stop drop through case happenning even for ID's less than final LWM otherwise
        $seen{$ID}++;
        
        # Finished with this ID, can stop reading through LWM's 
		last LWM;
    }
    
    # The drop through case when our ID is greater than the last LWM and the foreach loop over the LWM's has finished, so it must
	# be in the final LWM's changeset we cunningly saved away in $PrevLWM just in case we ran off the end of the LWM loop
    if(!exists $seen{$ID})
    {               
         # Go and print some output
		 printRecord($ID,$PrevLWM);
    }
}

# Print output	
sub printRecord
{
    my $ID=shift;
    my $LWM=shift;

    my $CCFile=$ID2File{$ID};
	my $ccversionpath=$ID2CCVerPath{$ID};
	
	# If this filename was reported as being skipped in the logile don't print anything (just return))
	if($cloakedFiles{$CCFile})
	{
		print "REM Skipping cloaked file $CCFile\n" if $verbose;
		return;
	}
			
	# Extract root paths, labels, changeset and comment for this ID from hashes we populated earlier
	my $ccrootpath=$ID2CCRootPath{$ID};
	my $tfsrootpath=$ID2TFSRootPath{$ID};
	
    my $Changeset=$LWM2CS{$LWM};
    my $Labels=$ID2Labels{$ID};
	my $comment=$ID2CCComment{$ID};
    
    # Swap path sep to TFS format "/" (clearcase path on windows is "\")
    (my $CCFilePSEPSwap = $CCFile) =~ s/\\/\//g;
    $ccrootpath =~ s/\\/\//g;
	
	# Substitute the clearcase root path to the TFS root path in the file path name to give the required/equivalant path of the file in TFS
	(my $TFSFile=$CCFilePSEPSwap) =~ s/$ccrootpath/$tfsrootpath/;

	if ($verbose)
	{
		print "\n";
		print "REM     ID ---------------------> $ID \n"            ;
		print "REM     tfsrootpath ------------> $tfsrootpath\n"    ;		
		print "REM     TFS File ---------------> $TFSFile\n"        ;		
		print "REM     Changeset --------------> $Changeset\n"      ;
		print "REM     Lowest ID in changeset -> $LWM\n"            ;
		print "REM     ccrootpath -------------> $ccrootpath\n"     ;		
		print "REM     Clearcase path ---------> $CCFile\n"         ;		
		print "REM     Clearcase version ------> $ccversionpath \n" ;
		print "REM     Clearcase comment ------> $comment \n"       ;
		
		if($Labels)
		{
			print "REM     Clearcase labels -------> $Labels\n\n" ;
		} 
		else
		{
			print "REM *** No labels on Clearcase version (so no TFS labelling command has been output below)\n"
		}
    }
    
	# Only print out if labels are present. 
    if($Labels)
    {
        # If comments contain "*" it confuses the migration tools lshistory parser which uses them as delimiters and format in log can get mixed up
        # So far have only seen once and normal label field was populated with parts of a multiline comment so checking here if label has 
        # embedded "*" as a start. Would normally expect to see a list of comma separated labels. Save to a warning variable to print at the
		# end as might get missed near top of long output.
		
        if ($Labels =~ /\*/)
        {
			# Save up warnings to display at end of output - use REM comment so will be ignored if output of this script is redirected into a bat file.
			$warnings .= "REM It looks like the comment contains one or more \"*\" which is likely to malform the\n";
			$warnings .= "REM parsed output of the cleartool lshistory command which uses \"*\" as a delimiter for the output. \n";
			$warnings .= "REM This can cause parts of the comment to end up in the label field of the output\n";
			$warnings .= "REM CHECK the label(s) carefully!!\n";
            $warnings .= "\n";
            $warnings .= "REM     ID ---------------------> $ID \n"            ;
            $warnings .= "REM     tfsrootpath ------------> $tfsrootpath\n"    ;		
            $warnings .= "REM     TFS File ---------------> $TFSFile\n"        ;		
            $warnings .= "REM     Changeset --------------> $Changeset\n"      ;
            $warnings .= "REM     Lowest ID in changeset -> $LWM\n"            ;
            $warnings .= "REM     ccrootpath -------------> $ccrootpath\n"     ;		
            $warnings .= "REM     Clearcase path ---------> $CCFile\n"         ;		
            $warnings .= "REM     Clearcase version ------> $ccversionpath \n" ;
            $warnings .= "REM     Clearcase comment ------> $comment \n"       ;
            $warnings .= "REM     Clearcase labels -------> $Labels\n\n" ;
        }
        
		# Split up labels in csv list so we print out one line per label
		my @Labels = split (/,/,$Labels);
        foreach my $Label (@Labels)
        {
            # Trim leading + trailing spaces
            $Label =~ s/^\s+//;
            $Label =~ s/\s+$//;
            
            # Print output, either mapping between file,changeset,label or tf.exe command. Can pipe to bat file and execute.
            print "$TFSFile | $Changeset | $Label\n" if $map;
            print "tf.exe label $Label /version:$Changeset /collection:$collection \"$TFSFile\"\n" if $labelcmd;
        }
		print "\n"; # Space between each filename
    }
}

# Print out any warnings at end of output, otherwise might get missed in a long stream of normal output
if($warnings)
{
	print "\n\n";
	print "REM ******************************* WARNINGS *********************************\n";
	print $warnings;
	print "REM **************************************************************************\n";
}

# Help message
sub usage
{
    print "Unknown option: @_\n" if ( @_ );
    print "\n";
	print "Purpose:\n";
	print "$0, a Perl script to generate commands to migrate labels from Clearcase to TFS following a migration using the Microsoft TFS Migration Toolkit.\n";
	print "\n";
	print "The script processes the logfile generated by the tool during a migration session from Clearcase to TFS. It doesn\'t require access to the original\n";
	print "Clearcase vob or the TFS Team Project to generate the labelling commands although it will require access to the Team Project when the commands are executed\n";
	print "Typically you would redirect the output into a bat file e.g. \"labelling_commands.bat\" and then execute it.\n";
	print "\n";
    print "Usage: perl $0 [options: -log -map -labelcmd -ccrootpath -tfsrootpath -verbose -help] > labelling_commands.bat\n";
    print "\n";
    print "As a minimum you need to specify:\n";
    print " - the TFS migration tool logfile path/name using -log \n";
    print " - the type of output with -map or -labelcmd (if you specify -labelcmd you also need to specify -collection)\n";
    print "\n";
    print "Options:\n";
    print "  -log             TFS migration tool logfile to process (required)\n";
    print "                   (default location C:\\Users\\<userid>\\AppData\\Local\\Microsoft\\Team Foundation\\TFS Integration Platform)\n";
    print "\n";
    print "  Type of output (required, either -map or -labelcmd)\n";
    print "  -map             Output a mapping file - format is \"filename | changeset | label\" \n";
    print "\n";
    print "  -labelcmd        Output labelling commands for the tf.exe command line tool \n";
    print "                   (if you specify -labelcmd you also need to specify -collection)\n";
    print "\n";
    print "  -collection      The TFS Team Project Collection (required if you specified -labelcmd). \n";
    print "                    e.g. https://istfod-tfs.bpweb.bp.com:8181/tfs/quantitative%20analytics\n";
    print "\n";
    print "  The following 2 root path values will be extracted from the logfile but can be over-ridden here if required (an unlikely scenario)\n";
	print "  and in the case of -ccrootpath would have to match actual paths in logfile to have any effect, whereas -tfsrootpath should work \n";
	print "  regardless of what the TFS server path actually is in the logfile.\n";
	print "\n";
    print "  -ccrootpath      Clearcase root path, essentially the left hand migration pair path, enclosed in single quotes e.g. \'\\QFC2\\QML\' \n";
    print "  -tfsrootpath     TFS root path, essentially the right hand migration pair path, no quotes e.g. \$/QCL/QCL-repo/trunk/QCL_Release \n";
    print "\n";
	print "\n";		
    print "  -help            Print this help/usage message\n";
    print "\n";
	print "  -verbose         Print out extra logging information like rootpaths, versions, labels etc. These extra information lines start\n";
	print "                   with the windows REM comment so they will be ignored if the script is run with -verbose and redirected \n";
	print "                   into a bat file and executed.\n";
	print "\n";
    print "Example 1: Output labelling commands after processing logfile QCL_QCL_Release.log for the QuantAnalytics Team Project:\n";
    print "\n";
    print "           perl $0 -log QCL_QCL_Release.log -labelcmd -collection https://istfod-tfs.bpweb.bp.com:8181/tfs/QuantAnalytics\n";
    print "\n";
	print "\n";
	print "Example 2: Output labelling commands after processing logfile QCL_QCL_Release.log for the QuantAnalytics Team Project\n";
	print "           and overide the TFS root path to \$/QCL/QCL-repo/trunk/QCL_Release\n";
    print "\n";
    print "           perl $0 -log QCL_QCL_Release.log -labelcmd -collection https://istfod-tfs.bpweb.bp.com:8181/tfs/QuantAnalytics\n";
	print "           -tfsroot  \$/QCL/QCL-repo/trunk/QCL_Release\n";
    print "\n";
	print "\n";
    print "Example 3: Output labelling commands after processing logfile QCL_QCL_Release.log for the QuantAnalytics Team Project\n";
	print "           and overide the clearcase root path to   '\\QFC2\\QML\'\n";
    print "\n";
    print "           perl $0 -log QCL_QCL_Release.log -labelcmd -collection https://istfod-tfs.bpweb.bp.com:8181/tfs/QuantAnalytics\n";
	print "           -ccrootpath \'\\QFC2\\QML\\'\n";
    print "\n";		
	print "\n";
    print "Example 4: Output mappings in format \"file|changeset|label\" after processing logfile _TfsMigrationShell_2012-04-12_21_26_17_part_0.log:\n";
    print "\n";
    print "           perl $0 -log _TfsMigrationShell_2012-04-12_21_26_17_part_0.log -map -collection https://istfod-tfs.bpweb.bp.com:8181/tfs/QuantAnalytics\n\n";
	print "\n";
	print "Author: Reg Smith - reg.smith\@uk.bp.com\n";
	print "May 2012\n";

    
    exit;
}

__END__
# A few notes on the logfile format follow:
# Higher in log file get lines with the cleartool lshistory output parsed up. e.g.
[02/04/2012 10:20:05] TfsMigrationShell.exe Information: 0 : VersionControl: ||536992463 | Checkin | version |  | 24/08/2011 19:56:48 |  | \QFC2\QCL\Source code\Kaluza\QCL_Kaluza\KaluzaBridge.cpp@@\main\10
# ..note if there was a multiline comment it spreads over multiple lines too as in this example (the newline is from comment itself):
[02/04/2012 10:20:05] TfsMigrationShell.exe Information: 0 : VersionControl: ||536992466 | Checkin | version | To add fliter for past data and volcalibration weights in AssetMarketData. 
[02/04/2012 10:20:05] Fix bugs in ScalarByTime method in vol function calibration | 25/08/2011 07:51:22 | QCL_Release_1.0.6.1 | \QFC2\QCL\Source code\Kaluza\QCL_Kaluza\AssetMarketData.cpp@@\main\3  
# Lower down get set of 4 lines that ties up change id (e.g. 536992466) with changeset (e.g. 227)
[02/04/2012 10:23:11] TfsMigrationShell.exe Information: 0 : VersionControl: Processing ChangeGroup #6633, change 536992466 
[02/04/2012 10:23:11] TfsMigrationShell.exe Information: 0 : VersionControl: Finished scheduling! 
[02/04/2012 10:23:15] TfsMigrationShell.exe Information: 0 : VersionControl: Checking in 4 items, owner  
[02/04/2012 10:23:15] TfsMigrationShell.exe Information: 0 : VersionControl: Checked in change 227
# So the idea is to map the label name to the filename+changeset as TFS refers to versions by way of changeset by trawling thorugh the file
# keeping track of filenames<->changeid and then changeid<->Changeset and from that generate a mapping file of label->filename_changeset
# To apply a label to a particular version of a file in TFS you refer to it by the changeset that version is in. The syntax for using
# the tf.exe command line tool is as follows - here we are applying the label called LABELNAME to the version of TradingWindows.h in
# changeset 230:
tf label LABELNAME /version:230 /collection:https://istfod-tfs.bpweb.bp.com:8181/tfs/quantitative%20analytics $/QFC2/RegTest1/TradingWindows.h





