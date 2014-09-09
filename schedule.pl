#!/usr/bin/perl

use strict;
use warnings;

#
#	ICal parser for computer science @ AAU
#	v1.0		- Initial version
#	v1.1+1.2	- Fix updating
#	v1.3		- Add timezone
#	v2.0		- Use new moodle, LWP::Simple -> LWP::UserAgent
#

#...
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

#Turn off output buffering
$|=1;


#Download
my $ScheduleData;
my $ua = LWP::UserAgent->new;
my $response = $ua->get('http://www.moodle.aau.dk/calmoodle/xml_kursusgange.php?semesterId=473&unixstart=1390176000&unixslut=1403222400');
if ($response->is_success) {
	$ScheduleData = $response->decoded_content;
} else {
	die $response->status_line;
}

#Parse
my $parser = new XML::Simple;
my $DOM = $parser->XMLin($ScheduleData);
my @Classes = @{ $DOM->{'kursusgang'} };

my $calendar = Data::ICal->new();
$calendar->add_properties(
	method => "REQUEST",
	#method => "CANCEL", #enable this to delete all events
	prodid => $calendar->product_id.' - //Cal for CS@AAU//JCCalv2.0//NONSGML Calendar',
	'X-WR-CALNAME' => 'CS@AAU DAT4 calendar',
	calscale => 'GREGORIAN',
	'X-WR-TIMEZONE' => 'Europe/Copenhagen'
);

my ($vtodo, $ICalNow, $summary);
foreach my $Class (@Classes) {

	$vtodo = Data::ICal::Entry::Event->new();
	$ICalNow = Date::ICal->new( epoch => time )->ical;
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
		summary => ($Class->{'kursus-navn'} eq "Computer Science 4") ? $Class->{'note'} : $Class->{'kursus-navn'},
		transp => "OPAQUE",
		organizer => 'JCCalClient' #apparently organizer doesn't like spaces...
	);
	
	$calendar->add_entry($vtodo);
}

my $cgi = new CGI;
print $cgi->header(-type => "text/calendar");
print $calendar->as_string;
