use LWP::UserAgent;
use JSON -support_by_pp;           
use Data::Dumper; 

#Fixing Swarm comment and activity keys that get "version": false, see  https://swarm.perforce.com/jobs/job095670
# For extra debugging can run with -s option like this to set DEBUG variable:
#  perl   -s .\fix-review-comments-version.pl -DEBUG

# Swarm server url and credentials
#my $address = "reg-xenial-vb";
#my $username = "reg";
#my $pass = "reg";

# For testing 
#my $review="15399";
#my $time2check="1591892211";
#my $commentKeyname = "C:/Users/Reg/cases/case674940/swarm-comment-0000001183";
#my $activityKeyname = "C:/Users/Reg/cases/case674940/swarm-activity-ffffcf12";

# When keys are stored in files
my $ReviewKeysSource = "C:/Users/Reg/cases/case674940/keys_20200904.log";
my $p4KeysComments = "C:/Users/Reg/cases/case674940/comment_keys_20200825.txt";
my $p4KeysActivities = "C:/Users/Reg/cases/case674940/activity_keys_20200825.txt";

##############################################################################
# Functions
##############################################################################
#
# - Given a time, return the version of review that it falls into.
#
#    getReviewVersionByTime($review,$time2check,$ReviewKeysSource,LAZY)
# 
# - Given a review, generate all the comment key names associated with that review 
#
#     commentsByReview ($review)
#
# - Given a comment key, check the version and generate corrected key
#
#     checkCommentVersion($commentKeyname)
#
# - Given an activity key, check the version and generate corrected key
#
#     checkActivityVersion($activityKeyname)
#
# - Given an activity, generate all the activity key names associated with that review 
#
#      activitiesByReview($review)
#
##############################################################################


#############################################
# Some use cases
#############################################

#############################################
# 1. Check a particular review's comment keys
#############################################

## Fetch a list of all comments for this review
#@commentKeysByReview = commentsByReview($review);

## Check each comment key for a valid version
#foreach my $commentKeyname (@commentKeysByReview) 
#{
#    print "#DEBUG 1  commentKeyname $commentKeyname\n"  if $DEBUG;
#    checkCommentVersion($commentKeyname);
#}
#########################################


##############################################
# 2. Check a particular review's activity keys
##############################################

## Fetch a list of all activities for this review
#@activityKeysByReview = activitiesByReview($review);

## Check each activity key for a valid version
#foreach my $activityKeyname (@activityKeysByReview) 
#{
#    print "#DEBUG 2 activityKeyname $activityKeyname\n"  if $DEBUG;
#    checkActivityVersion($activityKeyname);
#}
#########################################


##################################################################
# 3. Bulk check comments we have already filtered for "version":false
##################################################################
# For example by running
#
# p4 keys -e "swarm-comment*" | grep '"topic":"reviews' | grep '"version":false' > p4KeysComments.txt
##################################################################

# This would be running the p4 keys command directly
#foreach my $p4KeysComments (qx(p4 keys -e "swarm-comment*" | grep '"topic":"reviews' | grep '"version":false'))

# Reading comment keys from a file where we've put the output of p4 keys into a file 
# (so can get customer to send it without us needing to have p4 access to their server)
open(P4KEYSCOMMENTS, $p4KeysComments) or die "cannot open $p4KeysComments $!\n";
while (my $p4KeysComment = <P4KEYSCOMMENTS>)
{
    if($p4KeysComment =~ /^swarm-comment-/)
    {
        # We can cheat here to extract the key name and values since the name is fixed width
        my $commentKeyname = substr($p4KeysComment,0,24);
        my $comment_key_json = substr($p4KeysComment,27);
        
        print "#DEBUG 15 original comment $commentKeyname = $comment_key_json\n"  if $DEBUG;
        
        # use decode_json witchcraft to make it easier to extract data from json
        my $comment_key_decoded_json = decode_json( $comment_key_json );

        # Check version key exists and if it's non-integer lookup what review version it is from the time and generate corrected key.
        if (exists $comment_key_decoded_json->{'context'}{'version'} && $comment_key_decoded_json->{'context'}{'version'} !~ /^[1-9]{1,}$/)  
        {
            print "#DEBUG 3 $commentKeyname comment_version is false\n"  if $DEBUG;
            
            # Extract the time and review id from the comment key
            my $commentTime=$comment_key_decoded_json->{'time'};
            my $reviewID=$comment_key_decoded_json->{'context'}{'review'};
            
            # Get the review version the comment time falls into
            # $ReviewKeysSource is either 'p4' or filename with review keys
            my $correctedCommentVersion = getReviewVersionByTime($reviewID,$commentTime,$ReviewKeysSource,LAZY);
            
            # Update the version in the json object
            $comment_key_decoded_json->{'context'}{'version'} = $correctedCommentVersion;
            
            # Encode back to a serialised object and print out the p4 counter command to run 
            # (so we are not updating it here, rather outputting the command to run to update the comment key)
            
            # http://perl.mines-albi.fr/perl5.8.5/site_perl/5.8.5/JSON.html
            # According to JSON Grammar, slash (U+002F) is escaped. But by default JSON backend modules encode strings without escaping slash.
            # If $enable is true (or missing), then encode will escape slashes.

            $comment_key_encoded_json=JSON->new->utf8->escape_slash->encode($comment_key_decoded_json);

            print "p4 counter -u $commentKeyname \'$comment_key_encoded_json\'\n\n";
        }
    }
}

##################################################################
# 4. Bulk check activities we have already filtered for "version":false
##################################################################
# For example by running
#
# p4 keys -e "swarm-activity*" | grep '"topic":"reviews' | grep '"version":false' > p4KeysActivities.txt
##################################################################

# This would be running the p4 keys command directly
#foreach my $p4KeysActivities (qx(p4 keys -e "swarm-activity*" | egrep '("type":"comment"|"type":"review")' | grep '"version":false'))

# Reading activity keys from a file where we've put the output of p4 keys into a file 
# (so can get customer to send it without us needing to have p4 access to their server)
# open(P4KEYSACTIVITIES, $p4KeysActivities) or die "cannot open $p4KeysActivities $!\n";
# while (my $p4KeysActivity = <P4KEYSCOMMENTS>)
# {
    # if($p4KeysActivity =~ /^swarm-activity-/)
    # {
        # # We can cheat here to extract the key name and values since the name is fixed width
        # my $activityKeyname = substr($p4KeysActivity,0,23);
        # my $activity_key_json = substr($p4KeysActivity,28);
        
        # # use decode_json witchcraft to make it easier to extract data from json
        # my $activity_key_decoded_json = decode_json( $activity_key_json );
        

        # # Check version key exists and if it's non-integer lookup what review version it is from the time and generate corrected key.
        # if (exists $activity_key_decoded_json->{'context'}{'version'} && $comment_key_decoded_json->{'context'}{'version'} !~ /^[1-9]{1,}$/)  
        # {
            # print "#DEBUG 3 $commentKeyname comment_version is false\n"  if $DEBUG;
            
            # # Extract the time and review id from the comment key
            # my $commentTime=$comment_key_decoded_json->{'time'};
            # my $reviewID=$comment_key_decoded_json->{'context'}{'review'};
            
            # # Get the review version the comment time falls into
            # # $ReviewKeysSource is either 'p4' or filename with review keys
            # my $correctedCommentVersion = getReviewVersionByTime($reviewID,$commentTime,$ReviewKeysSource,LAZY);
            
            # # Update the version in the json object
            # $comment_key_decoded_json->{'context'}{'version'} = $correctedCommentVersion;
            
            # # Encode back to a serialised object and print out the p4 counter command to run 
            # # (so we are not updating it here, rather outputting the command to run tp update the comment key)
            # $comment_key_encoded_json=encode_json($comment_key_decoded_json);
            # print "p4 counter -u $commentKeyname \'$comment_key_encoded_json\'\n\n";
        # }
    # }
# }

###########
# Functions
###########
# Given a comment key, check the version and if it's non-integer generate corrected key
sub checkCommentVersion {
    
    my $commentKeyname = shift;
    
    #  Get comment key from "p4 keys" using formatted form of p4 command to output just the key value)
    my $comment_key_json=qx(p4 -ztag -F "%value%" keys -e $commentKeyname);

    # use decode_json witchcraft to make it easier to extract data from json
    my $comment_key_decoded_json = decode_json( $comment_key_json );


    print Dumper($comment_key_decoded_json)  if $DEBUG;
    
    print "comment_key_decoded_json->{'context'}{'version'}" . $comment_key_decoded_json->{'context'}{'version'} . "ver=" . $commentkeyVersion . "\n" if $DEBUG;
    

    
    # Check version key exists and if it's non-integer lookup what review version it is from the time and generate corrected key.
    if (exists $comment_key_decoded_json->{'context'}{'version'} && $comment_key_decoded_json->{'context'}{'version'} !~ /^[1-9]{1,}$/)     
    {    

        print "#DEBUG 4 $commentKeyname comment_version is non-integer\n"  if $DEBUG;
        
        # Extract the time and review id from the comment key
        my $commentTime=$comment_key_decoded_json->{'time'};
        my $reviewID=$comment_key_decoded_json->{'context'}{'review'};
        
        # Get the review version the comment time falls into
        my $correctedCommentVersion = getReviewVersionByTime($reviewID,$commentTime,$ReviewKeysSource,LAZY);
        
        print "#DEBUG 5 $commentKeyname time $commentTime reviewID $reviewID correctedCommentVersion $correctedCommentVersion\n"  if $DEBUG;
        
        # Update the version in the json object
        $comment_key_decoded_json->{'context'}{'version'} = $correctedCommentVersion;
        
        # Encode back to a serialsed object and print out the p4 counter command to run 
        # (so we are not updating it here, rather outputting the command to run tp update the comment key)
        #$comment_key_encoded_json=encode_json($comment_key_decoded_json);
        
        $comment_key_encoded_json=JSON->new->utf8->escape_slash->encode($comment_key_decoded_json);
        
        print "p4 counter -u $commentKeyname \'$comment_key_encoded_json\'\n\n";
    }
}


# Given an activity key, check the version and generate corrected key
sub checkActivityVersion {
    
    my $activityKeyname = shift;
    
    #  Get activity key from "p4 keys" using formatted form of p4 command to output just the key value)
    my $activity_key_json=qx(p4 -ztag -F "%value%" keys -e $activityKeyname);

    # use decode_json witchcraft to make it easier to extract data from json
    my $activity_key_decoded_json = decode_json( $activity_key_json );
    
    # checking the version only really makes sense in the context of a comment or review activity (I think?)
    my $activityType=$activity_key_decoded_json->{'type'};
    return unless ($activityType eq "comment" || $activityType eq "review");

    print "#DEBUG 6 activityKeyname $activityKeyname activity_version $activity_version " . $activity_key_decoded_json->{'link'}[1]{'version'} . "\n" if $DEBUG;
    
    # Check version key exists and if it's non-integer lookup what review version it is from the time and generate corrected key. 
    if (exists $activity_key_decoded_json->{'link'}[1]{'version'} && $activity_key_decoded_json->{'link'}[1]{'version'} !~ /^[1-9]{1,}$/) 
    {  
        print "#DEBUG 7 $activityKeyname activity version is non integer\n" if $DEBUG;
        print Dumper($activity_key_decoded_json) if $DEBUG;
        
        # Extract the time from the activity key
        my $activityTime=$activity_key_decoded_json->{'time'};
        
        print "#DEBUG 8 activityTime $activityTime\n" if $DEBUG;
        
        # Extract the review from the activity key
        my $reviewID=$activity_key_decoded_json->{'link'}[1]{'review'};
        
        print "#DEBUG 9 reviewID $reviewID\n" if $DEBUG;
        
        # Get the review version the comment time falls into
        my $correctedActivityVersion = getReviewVersionByTime($reviewID,$activityTime,$ReviewKeysSource,LAZY);
        
        print "#DEBUG 10 correctedActivityVersion $correctedActivityVersion\n" if $DEBUG;
         
        # Update the version in the json object
        $activity_key_decoded_json->{'link'}[1]{'version'} = $correctedActivityVersion;
        
        # Encode back to a serialsed object and print out the p4 counter command to run 
        # (so we are not updating it here, rather outputting the command to run tp update the comment key)
        #$activity_key_encoded_json=encode_json($activity_key_decoded_json);
        $activity_key_encoded_json=JSON->new->utf8->escape_slash->encode($activity_key_decoded_json);

        print "p4 counter -u $activityKeyname \'$activity_key_encoded_json\'\n\n";   
    }
}

# Given a time, return the version of review that it falls into
sub getReviewVersionByTime {
    my ($review,$time2check,$ReviewKeysSource,$lazy)=@_;
    
    my $review_key_decoded_json, $review_key_json;
    
    
    # Generate key name from review id
    my $reviewKeyname = "swarm-review-". lc(sprintf("%X", 4294967295 - $review));
    print "#DEBUG 11 Review $review Keyname = $reviewKeyname Time $time2check\n" if $DEBUG;

    # Get review key, either from "p4 keys" or from a file that has a dump of review keys

     # Get review key from p4 connection
    if($ReviewKeysSource eq "p4")
    {    
        # Get review key from "p4 keys" using formatted form of p4 command to output just the key value)
        $review_key_json=qx(p4 -ztag -F "%value%" keys -e $reviewKeyname);
    
    
        # use decode_json witchcraft to make it easier to extract data from json
        $review_key_decoded_json = decode_json( $review_key_json );
    }    
    else
    {
        # Else get review key from a file containing "p4 keys" output for reviews 
        # So can get customer to send it without us needing to have p4 access to their server)
    
        # Only need to read the file once and store the key/value in a hash $reviewKeys=$reviewKeyname{$jsonkey} 
        # that we can then lookup from the hash rather than reading the review data from the file.
        unless ($readReviewKeyfile) 
        {
            open(REVIEWKEYS, $ReviewKeysSource) or die "cannot open $ReviewKeysSource $!\n";
            undef %seenReview;
            while (my $p4KeysReview = <REVIEWKEYS>)
            {
                chomp $p4KeysReview;
                
                if($p4KeysReview =~ /^swarm-review-/)
                {
                    print "#DEBUG 13.1 Review key from file = $p4KeysReview\n" if $DEBUG;
                     
                    # We can cheat here to extract the key name and values since the name is fixed width
                    my $review_key_name = substr($p4KeysReview,0,21);
                    my $review_key_json = substr($p4KeysReview,24);
                    
                    if (!exists($seenReview{$review_key_name})) 
                    { 
                        $seenReview{$review_key_name} = 1;
                        $reviewKeynames{$review_key_name} = $review_key_json;
                        
                        print "#DEBUG 13.2 REVIEW Keyname  = $review_key_name\n" if $DEBUG;
                        print "#DEBUG 13.3 REVIEW Keyvalue = $review_key_json\n" if $DEBUG;
                    }
                }                
            }
            # We've read it now
            print "#DEBUG 13.5 **********************************************************************\n" if $DEBUG;
            print "#DEBUG 13.5 ***************************** finished populating hash %reviewKeynames\n" if $DEBUG;
            print "#DEBUG 13.5 **********************************************************************\n" if $DEBUG;
            
            $readReviewKeyfile=1;
            close REVIEWKEYS;
        }
        
        # use decode_json witchcraft to make it easier to extract data from json
        #my $review_key_decoded_json = decode_json( $review_key_json ->[0] );
        
        
        print "#DEBUG 13.4 json stored in reviewKeynames{$reviewKeyname}= $reviewKeynames{$reviewKeyname}\n" if $DEBUG;
        
        $review_key_decoded_json = decode_json( $reviewKeynames{$reviewKeyname} );
        
    }


    
    # Extract the versions blocks into array
    my @versions = @{ $review_key_decoded_json->{'versions'} };
    my $num_versions=scalar @versions;
    
    print "#DEBUG 14 num_versions= $num_versions\n" if $DEBUG;

    # populate a hash with each review version's time
    for my $version_num (1..$num_versions) 
    {
        my $time = $versions[${version_num}-1]->{'time'};
        
        # Basic sanity check, should never really see a comment with a time earlier than the creation time of the review
        if($time2check < $time &&  $version_num == 1)
        {
                print "$time2check is earlier than the creation time $time of verison 1 of review $review";
                return "TOOEARLY";
        }
       
        # We can pass in a "lazy" argument to bail out as soon as we have the version More efficient if we are only
        # processing a single review and don't need to bother storing a hash of every review+version time. 
        # Not actually implemented using it yet though
        if ($time2check >= $time)
        {
            $version_number=$version_num;
            if(!$lazy)
            {
                 $review{$version_num} = $time;
            }            
        }
        else
        {
            if($lazy)
            {
                    return $version_number;
            }          
        }
    }
    print "#DEBUG 15 version_number= $version_number\n" if $DEBUG;
    return $version_number;
}

# Given a review, generate all the comment key names associated with that review (and do anything else you want)
sub commentsByReview {
    
    my $review = shift;
    
    # It's slower using the api but this way the api only return just the comments for this review. 
    # While "p4 keys" is a lot faster for extracting keys, for comments we would have to dump all
    # swarm-comment-* keys and extract those with a "topic":reviews/{review-number}" which for a large
    # number of comments is going to be expensive.
    
    my $url="http://$address/api/v9/comments?topic=reviews/$review";
    
    my $browser = LWP::UserAgent->new;
    my $req =  HTTP::Request->new( GET => $url);
    $req->authorization_basic( "$username", "$pass" );
    my $response = $browser->request( $req );
    my $content = $response->content();
    my $decoded_json = decode_json( $content );
    
    my @comments = @{ $decoded_json->{'comments'} };
    foreach $comment ( @comments ) 
    {
        my $time = $version->{"time"};
        my $comment_id = $comment->{'id'} ;
        my $comment_version = $comment->{'context'}{'version'} ;
        
        my $comment_key_name="swarm-comment-" . "0" x (10 - length $comment_id) . $comment_id;
        
        push @comment_key_names, $comment_key_name;
    
        print "#DEBUG 12 review $review , comment \n $comment , \n comment_id $comment_id comment_version $comment_version\n" if $DEBUG;
    }
    
    return @comment_key_names;
}

# Given a review, generate all the activity key names associated with that review
sub activitiesByReview {
    
    my $review = shift;
    
    # It's slower using the api but this way the api only return just the activities for this review. 
    # While "p4 keys" is a lot faster for extracting keys, for comments we would have to dump all
    # swarm-comment-* keys and extract those with a "topic":reviews/{review-number}" which for a large
    # number of comments is going to be expensive.
    
    my $url="http://$address/api/v9/activity?topic=reviews/$review";
    
    my $browser = LWP::UserAgent->new;
    my $req =  HTTP::Request->new( GET => $url);
    $req->authorization_basic( "$username", "$pass" );
    my $response = $browser->request( $req );
    my $content = $response->content();
    my $decoded_json = decode_json( $content );
    
    my @activities = @{ $decoded_json->{'activity'} };
    foreach $activity ( @activities ) 
    {
        my $time = $activity->{"time"};
    
        my $activity_id = $activity->{'id'} ;
        
        # Generate activity key name from activity id
        my $activity_keyname = "swarm-activity-". lc(sprintf("%X", 4294967295 - $activity_id));
        
        #my $activity_version = $activity->{'link'}[1]{'version'} ;
        
        push @activity_key_names, $activity_keyname;
    }
    
    return @activity_key_names;
}
exit;

# Alternative method, get the review key versions from Swarm api endpoint

# Swarm server url and credentials
my $address = "reg-xenial-vb";
my $username = "reg";
my $pass = "reg";
my $url="http://$address/api/v9/reviews/${review}?fields=versions";

#print $url;
my $browser = LWP::UserAgent->new;
my $req =  HTTP::Request->new( GET => $url);
$req->authorization_basic( "$username", "$pass" );
my $response = $browser->request( $req );
my $content = $response->content();
my $decoded_json = decode_json( $content );


#print Dumper($decoded_json);

my @versions = @{ $decoded_json->{'review'}{'versions'} };
$num_versions=scalar @versions;

#print "Review $review has $num_versions versions\n";

# populate a hash with each review's version's time
$version_num=1;
foreach $version ( @versions ) {
    $time = $version->{"time"};
    #print "Version $version_num == $time\n";
    
    $review{$version_num} = $time;
    $version_num++;
}    

# Another way, count up through the version numbers and specify array index to get to the time
#for my $version (1..$num_versions) 
#{
#    print "version $version , time=" . $decoded_json->{'review'}{'versions'}[${version}-1]{'time'} . "\n";
#}

#print "review $review hash dump \n";
foreach my $version (sort keys %review)
{
  my $time = $review{$version};
  print "review $review version $version created $time\n";
}

###################################
# p4 comment keys in a file (so can get customer to send it without us needing to have p4 access to their server)
open(P4KEYSCOMMENTS, "comment_keys_20200825.txt") or die "cannot open $!\n";
undef %seen;
while (my $p4KeysComments = <P4KEYSCOMMENTS>)
{
    # We can cheat here to extract the key name and values since the name is fixed width
    my $comment_key_json = substr($p4KeysComments,27);
    my $comment_key_decoded_json = decode_json( $comment_key_json );
    my $reviewID=$comment_key_decoded_json->{'context'}{'review'};
    
    # Generate key name from review id
    my $review_keyname = "swarm-review-". lc(sprintf("%X", 4294967295 - $reviewID));
    
    if (!exists($seen{$review_keyname})) 
    { 
        $seen{$review_keyname} = 1;
        print "p4 keys -e \"$review_keyname\"\n";
    }
}

# p4 activity keys in a file (so can get customer to send it without us needing to have p4 access to their server)
# "type":"comment","link":["review",{"review":1150558,"fragment":"7fa9753091e981270514b2ffbca033d5,c5925","version":false}]

open(P4KEYSACTIVITIES, "activity_keys_20200825.txt") or die "cannot open $!\n";
#undef %seen;
while (my $p4KeysActivities = <P4KEYSACTIVITIES>)
{
    # We can cheat here to extract the key name and values since the name is fixed width
    my $activityKeyName = substr($p4KeysActivities,0,23);
    my $activity_key_json = substr($p4KeysActivities,26);
    
    my $activity_key_decoded_json = decode_json( $activity_key_json );
    next unless $activity_key_decoded_json->{'type'} eq "comment";
    
    my $reviewID=$activity_key_decoded_json->{'link'}[1]{'review'};
    
    # Generate key name from review id
    my $review_keyname = "swarm-review-". lc(sprintf("%X", 4294967295 - $reviewID));
    
    if (!exists($seen{$review_keyname})) 
    { 
        $seen{$review_keyname} = 1;
        print "p4 keys -e \"$review_keyname\"\n";
    }
}

