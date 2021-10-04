#!/usr/bin/perl

# Reg Smith
# Report on any depot paths used in more than one project branch path
# Also report on branches paths that overlap (common parent), where a project branch
# is a parent of another project's branches

# The report output will:

# - list each project and and its branches list
# - list branches and associated projects with exact matches where the same branches are used in multiple projects
# - list branches and associated projects with overlaps (common parents).

 
use JSON qw( decode_json );     # From CPAN
use File::Basename;
 
# Dump project details from p4 keys command if script invoked with "perl -s reportBranchesMultipleProjects.pl -p4", else read keys from file
if ($p4)
{
	open (PROJECTKEYS, "p4 -ztag -F %value% keys -e swarm-project-* |") or die "Cannot open p4 keys command $!\n";
}
else
{
	# Alternatively for rapid debugging read json keys from file project-keys.txt
	open (PROJECTKEYS, "project-keys.txt") or die "Cannot open project-keys.txt $!\n";
}

foreach my $projectKey (<PROJECTKEYS>)
{
    chomp $projectKey;
   
    # Use json library to parse/decode json
    my $decoded_json = decode_json( $projectKey );
 
    # Ignore deleted projects which have deleted set to true
    next if $decoded_json->{'deleted'} eq 1;
 
    # Extract branches array which contains array of hash refs
    my @branches = @{ $decoded_json->{'branches'} };
 
    # Project name
    my $project = $decoded_json->{'name'} ;
   
    # Loop over branches array
    foreach my $f ( @branches ) {
		
		my $branchID=$f->{"id"};
   
        # loop over paths array refs
        foreach my $paths ($f->{"paths"})
        {
            #$paths is an array ref to array containing all the paths for the project branch
            foreach my $path ( @$paths )
            {
				# Branch paths should always end in ... but seem to have some that don't so warn and skip. Messes up matching
				if ($path !~ /\.\.\.$/){
					print "WARNING - Project [$project] BranchID [$branchID] Path [$path] not in depot syntax (should have ... suffix, ignoring)\n"; 
					next;
				}
				
				#Ignore exclusionary filepaths (those starting with - character) 
	            next if $path =~ /^\-/;
                
				# If we haven't seen this path already store it in pathProjects hash
                next if (grep /^$project$/, @{$pathProjects{$path}});
				
				push @{$pathProjects{$path}}, "$project" ; 
 
                # If we haven't seen this path already store it in projectPaths hash
                if (!exists($projectPaths{$path})) { $projectPaths{$path} = 1;}
                
				# If we have seen it before then it's been used in more than one project
				else {$pathsMultipleProjects{$path}=1};
            }
        }
    }
    }
	
	print "\n\n*************************************************\n";
	print "************** Exact path matches ***************\n";
	print "*************************************************\n";
    foreach my $path (sort keys %pathsMultipleProjects) {
 
        # Get all the projects that use this path
        my @projects=@{$pathProjects{$path}};
 
        print "Path $path used in " . scalar(@projects) . " project(s) [" . join ("/",@projects ) . "]\n";
	}		
	
# Report paths that are parents of other paths

print "\n\n*****************************************************************\n";
print "************** Common parent branch path overlaps ***************\n";
print "*****************************************************************\n";

@allpaths = sort keys(%projectPaths);

foreach my $path (@allpaths)
{
	my($filename, $directory) = fileparse($path);
	$parent = dirname($directory) . "\/";
	
	# Ignore a parent that is very top level //, pointless checking this for overlaps as every path will have this
	next if $parent =~ /^\/\/$/;
	
	$pathNoEllipsis = substr($path, 0, -3);
	
	my @childPaths = grep {/^\Q$pathNoEllipsis\E/} @allpaths;
	
	foreach my $childPath (@childPaths)
	{	
		
		# Skip over childPath and path the same, it's found itself;
		next if $childPath eq $path;		

		# Get all the projects that use path or child paths, skip if no associated projects 
		my @projects=@{$pathProjects{$path}};
		next if scalar @projects == 0;
		
		my @childProjects=@{$pathProjects{$childPath}};
		next if scalar @childProjects == 0;
 
        print "Path $path used in " . scalar(@projects) . " project(s) [" . join ("/",@projects) . "] is a parent path of $childPath used in " . scalar(@childProjects) . " project(s) [" .  join ("/",@childProjects) . "]\n";
	 
	} 
}
	
exit;