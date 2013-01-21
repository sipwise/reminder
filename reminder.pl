#!/usr/bin/perl -w
use strict;

use File::Temp qw(tempfile);
use File::Basename;
use File::Copy;
use DBI;

our $weekdays;
our $retries;
our $retry_time;
our $wait_time;
our $context;
our $sip_peer;
our $spool;
our $tmpdir;

our $database;
our $dbhost;
our $dbuser;
our $dbpassword;


my $config_file = "/etc/ngcp-reminder/reminder.conf";
open CONFIG, "$config_file" or die "Program stopping, couldn't open the configuration file '$config_file'.\n";

while (<CONFIG>) {
    chomp;                  # no newline
    s/#.*//;                # no comments
    s/^\s+//;               # no leading white
    s/\s+$//;               # no trailing white
    next unless length;     # anything left?
    my ($var, $value) = split(/\s*=\s*/, $_, 2);
        no strict 'refs';
        $$var = $value;
}
close CONFIG;

if(!defined $weekdays || $weekdays =~ /^\s*$/) {
	$weekdays = '2,3,4,5,6,7';
}
my @wdays = split /\s*,\s*/, $weekdays;

my $dsn = "DBI:mysql:database=$database;host=$dbhost;port=0";


my $dbh = DBI->connect($dsn, $dbuser, $dbpassword);

my $sth = $dbh->prepare("SELECT a.username, b.domain, c.recur, c.id " .
	"FROM voip_subscribers a, voip_domains b, voip_reminder c " .
	"WHERE c.subscriber_id = a.id and a.domain_id = b.id " . 
	"and c.time = time_format(now(), '%H:%i:00')");

my $sth_d = $dbh->prepare("delete from voip_reminder where id=?");

$sth->execute;
while (my $ref = $sth->fetchrow_hashref()) 
{
	print "$ref->{'username'}\@$ref->{'domain'}, recur=$ref->{'recur'}\n";

	if($ref->{'recur'} eq "weekdays")
	{
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time);
		$wday++; # make sun=1, sat=7
		next unless(grep(/^$wday$/, @wdays));
	}

	my ($tmp, $tmp_filename) = tempfile("$ref->{'username'}.XXXXXX", DIR => $tmpdir, UNLINK => 0);
	unless(defined $tmp)
	{
		die "Failed to create temporary call file: $!\n";
	}

	print "Using tmpfile '$tmp_filename'\n";

	print $tmp "Channel: SIP/$sip_peer/$ref->{'username'}__AT__$ref->{'domain'}\n";
	print $tmp "MaxRetries: $retries\n";
	print $tmp "RetryTime: $retry_time\n";
	print $tmp "WaitTime: $wait_time\n";
	print $tmp "Extension: s\n";
	print $tmp "Context: $context\n";
	print $tmp "Priority: 1\n";
	close $tmp;
	move "$tmp_filename", "$spool/".basename($tmp_filename)
		or die "Failed to move call '$tmp_filename' file to spool: $!\n";
	
	if($ref->{'recur'} eq "never")
	{
		$sth_d->execute($ref->{'id'});
	}
}

$sth->finish;

