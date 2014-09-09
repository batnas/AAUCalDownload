#!/usr/bin/perl

use strict;
use warnings;

#
#       ICal parser for computer science @ AAU
#       v1.0        - Initial version
#       v1.1+1.2    - Fix updating
#       v1.3        - Add timezone
#       v2.0        - Use new moodle, LWP::Simple -> LWP::UserAgent
#       v3.0        - Accept parameters by CGI
#       v3.1        - Accept multiple ignore parameters
#

#sources
#http://www.caveofprogramming.com/perl/perl-downloading-and-parsing-xml/
#http://www.perlmonks.org/?node_id=558182
#http://stackoverflow.com/questions/18412533/perl-dataical-print-event-time-as-t000000z-instead-of-omitting-it
#http://stackoverflow.com/questions/45453/icalendar-and-event-updates-not-working-in-outlook


#For parsing
use XML::Simple;

#For downloading
use LWP::UserAgent;

#For debug output
use Data::Dumper;

#For ICal support
use Data::ICal;
use Data::ICal::Entry::Event;
use Date::ICal;

#To being able to print to web
use CGI;

#Convert month+year to epoch
use Time::Local;

#Turn off output buffering
$|=1;


#variables
my ($sid, @ignores, $ignore, $unixstart, $unixslut, $semester, $course);
my $BaseURL='https://www.moodle.aau.dk/calmoodle/xml_kursusgange.php';
my $Name = "JCCal";
my $Version = "3.0";
my $cgi = new CGI;


#parse input
$sid = $cgi->param("sid");
$sid = "" if ! defined $sid;
if ( $sid ne "" ) { $sid =~ s/[^0-9]*//g; }
if ( $sid eq "" ) { $sid = "776"; }

@ignores = $cgi->param("ignore");
for my $i (0 .. $#ignores) {
    if ( $ignores[$i] ne "" ) { $ignores[$i] =~ s/[;&]*//g; }
}

$unixstart = $cgi->param("unixstart"); 
$unixstart = "" if ! defined $unixstart;
if ( $unixstart ne "" ) { $unixstart =~ s/[^0-9]*//g; }
if ( $unixstart eq "" ) {
    #generate default
    my ($mon,$year) = (localtime(time))[4,5];
    if ($mon >=1 and $mon <=5) { #Feb to Jun - Spring semester
        ($mon, $year) = (1, $year+1900); #1st Feb
    } elsif (  $mon >=8  or $mon == 0 ) { #Sep to Dec + Jan - Fall semester
        if ($mon == 0) {$year--;}
        ($mon, $year) = (8, $year+1900); #1st Sep
    }
    $unixstart = timelocal(0,0,0,1, $mon,$year);
}

$unixslut = $cgi->param("unixslut"); 
$unixslut = "" if ! defined $unixslut;
if ( $unixslut ne "" ) { $unixslut =~ s/[^0-9]*//g; }
if ( $unixslut eq "" ) {
    #generate default
    my ($mon,$year) = (localtime(time))[4,5];
    if ($mon >=1 and $mon <=5) { #Feb to Jun - Spring semester
        ($mon, $year) = (6, $year+1900); #1st Jul
    } elsif (  $mon >=8  or $mon == 0 ) { #Sep to Dec + Jan - Fall semester
        if ($mon != 0) {$year++;}
        ($mon, $year) = (0, $year+1900); #1st Jan
    }
    $unixslut = timelocal(0,0,0,1, $mon,$year);
}

$semester = $cgi->param("semester");
$semester = "" if ! defined $semester;
if ( $semester ne "" ) { $semester =~ s/[^0-9]*//g; }
if ( $semester eq "" ) { $semester = "5"; }

$course = $cgi->param("course");
$course = "" if ! defined $course;
if ( $course ne "" ) { $course =~ s/[^a-zA-Z ]*//g; }
if ( $course eq "" ) { $course = "Computer Science"; }


#Download
my $ScheduleData;
my $ua = LWP::UserAgent->new;
my $URL = $BaseURL . "?semesterId=" . $sid . "&unixstart=" . $unixstart . "&unixslut=" . $unixslut;

my $response = $ua->get($URL);
die $response->status_line if (! $response->is_success);

$ScheduleData = $response->decoded_content;


#Parse
my $parser = new XML::Simple;
my $DOM = $parser->XMLin($ScheduleData);
my @Classes = @{ $DOM->{'kursusgang'} };


#build ICal
my $calendar = Data::ICal->new();
$calendar->add_properties(
    method => "REQUEST",
    #method => "CANCEL", #enable this to delete all events
    prodid => $calendar->product_id.' - //Cal for AAU//'.$Name.'v'.$Version.'//NONSGML Calendar',
    'X-WR-CALNAME' => 'CS@AAU ' . $course . ' ' . $semester . ' calendar',
    calscale => 'GREGORIAN',
    'X-WR-TIMEZONE' => 'Europe/Copenhagen'
);

my ($vtodo, $ICalNow, $fullsemester);
EVENTS:
foreach my $Class (@Classes) {
    foreach $ignore (@ignores) {
        next EVENTS if ( index($Class->{'kort-beskrivelse'}, $ignore) != -1 );
    }

    $vtodo = Data::ICal::Entry::Event->new();
    $ICalNow = Date::ICal->new( epoch => time )->ical;
    $fullsemester = $course." ".$semester;

    $vtodo->add_properties(
        dtstart => Date::ICal->new( epoch => $Class->{'unixtime-start'} )->ical,
        dtend => Date::ICal->new( epoch => $Class->{'unixtime-slut'} )->ical,
        dtstamp => $ICalNow,
        created => $ICalNow,
        uid => $Class->{'kursusgang-id'}.'@cs.aau.dk',
        description => $Class->{'kort-beskrivelse'}, #beskrivelse
        'last-modified' => $ICalNow,
        location => $Class->{'lokale-navn'},
        sequence => time,
        status => "CONFIRMED", 
        #status => "CANCELLED", #enable this to cancel all events
        summary => ($Class->{'kursus-navn'} =~ /\Q$fullsemester\E/) ? $Class->{'note'} : $Class->{'kursus-navn'},
        transp => "OPAQUE",
        organizer => $Name."Client" #apparently Data::ICal doesnt like spaces
    );

    $calendar->add_entry($vtodo);
}

print $cgi->header(-type => "text/calendar");
print $calendar->as_string;
