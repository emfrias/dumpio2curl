#!/usr/bin/perl

use strict;
use warnings;
use 5.010;

my %lines_by_pid;

while(<>) {
    # Peal off the Apache log format
    # This can be found in the source code /server/log.c do_errorlog_default()
    # I believe it can be changed via config, but if you break it you can fix it
    my ($timestamp, $pid_str, $client, $log_msg) = /^
	    \[([^\]]*)\] \s+    (?# Date in ctime format )
	    \[dumpio:\w+\] \s+  (?# Module name : log level - typically trace7 )
	    \[([^\]]+)\]        (?# process and thread id if applicable "pid ###" or "pid ###:tid ###" )
				(?# If log level >= debug, the filename and line number are here )
				(?# If status is set it is output here )
	    .*                  (?# Discard the above two possible bits of information)
	    \[client\s+([^\]]+)\] \s+ (?# Client identification details, ip:port )
				(?# Above client may be "remote", we don't want them )
	    (.*?)               (?# The actual specific log message)
	    \r?\n$
    /x;
    next unless defined($timestamp);
    # We only want the data packets, defined above as dumpit() #87 & #100
    # "mod_dumpio:  %s (%s-%s): %s"
    my ($direction, $data) = $log_msg =~ /^mod_dumpio: \s+ dumpio_(\w+) \s+ \((?:meta)?data-\w+\): \s+ (.*)$/x;

    next unless defined($direction); # Didn't match
    next unless $direction eq "out" or $direction eq "in"; # Shouldn't happen, but better safe

    if (exists $lines_by_pid{$pid_str}) {
        $lines_by_pid{$pid_str} .= $_;
    } else {
        $lines_by_pid{$pid_str} = $_;
    }

    if (/metadata-EOC/) {
        print $lines_by_pid{$pid_str};
        delete $lines_by_pid{$pid_str};
    }
}
for (values(%lines_by_pid)) {
    print;
}

=head1 NAME

dumpio2curl_demuxer.pl - demultiplexes an apache dumpio log file that will be in put to dumpio2curl.pl

=head1 USAGE

dumpio2curl_demuxer.pl apache.log | dumpio2curl.pl

=head1 DESCRIPTION

On a webserver handling multiple simultaneous connections, mod_dumpio will multiplex the log
messages for all the streams into the same log file, which confuses dumpio2curl.pl and causes
it to print:
    Expected request entry, line xxx
This program reformats the log file so that all log lines for each connection are contiguous.
