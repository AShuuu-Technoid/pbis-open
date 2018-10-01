#!/usr/bin/perl
# Copyright 2008-2011 Likewise Software, 2011-2014 BeyondTrust Software
# by Robert Auch
# gather information for emailing to support.
#
#
#
# run "perldoc pbis-support.pl" for documentation
#

#
#
#
# v0.1 2009-06-12 RCA - first version, build structures from likewise-health-check.sh
# v0.2 2009-06-23 RCA - add agent restarts with logging
# v0.3 2009-06-24 RCA - add ssh tests and other info gathering for the logfile
# v0.4 2009-06-25 RCA - tarball complete - moving to beta stage
# v0.5b 2009-06-25 RCA - cleaning up Mac support
# v0.6b 2009-06-25 RCA - daemon restarts cleaned up and stable.
# v0.7b 2009-06-28 RCA - edit syslog.conf and set "lw-set-log-level" if --norestart
# v0.8b 2009-07-06 RCA - Solaris and AIX support fixups
# v0.9b 2009-07-08 RCA - PAC info gathering if any auth tests are attempted and sudoers file gather
# v1.0 2009-07-28 RCA - turn on auth tests always, tested on Solaris 9, 10, AIX 5, HP-UX 11.23, 11.11, RHEL 3,4,5, Ubuntu 8,9, Suse 9,10, and Mac OSX10.5 as working. Works on Solaris 8 if Perl upgraded to at least 5.6
# v1.1 2009-08-14 RCA - clean up version information to getLikewiseVersion only, add inclusion of /etc/likewise and timezone data
# v1.1.1 2009-08-20 RCA - gather samba logs (option)
# v1.1.2 2009-08-20 RCA - write out options passed
# v1.1.3 2009-09-10 RCA - documentation updates, and better hunt for smb.conf
# v1.2.0 2009-10-01 RCA - Changes based on CR by Danilo
# v1.2.1 2009-11-04 RCA - Daemon Restart rewrite
# v1.2.2 2009-12-12 RCA - Tool modularity update
# v1.2.3 2009-12-22 RCA - rewrite signal handling
# v1.2.4 2010-03-18 RCA - support Solaris 10 svcs commands properly
# v1.3 2010-09-28 RCA - support LW 6.
# v2.0 2010-09-28 RCA - support LW 6 fully.
# v2.0.1b 2011-04-11 RCA - PID matching and process shutdown improvements
# v2.0.2b 2011-04-13 RCA - Mac restart issue fixes
# v2.5.0  2013-02-11 RCA PBIS 7.0 (container) support
# v2.5.1  2013-06-13 RCA config dump, code cleanup, logfile locations.
# v2.5.2  2013-08-12 RCA fix up DNS, runTool for large environments using open() rather than ``
# v2.5.3  2013-10-15 RCA - add new "action" command to runTool() solves "out of memory" error during enum-users
# v2.5.4  2013-12-12 RCA fix up SELinux breakage, capture selinux audit log for Permissive/Enforcing environments
# v2.6.0  2014-04-11 RCA add -dj option and cleanups for different domainjoin-cli commands
# v2.6.1  2014-08-07 RCA selinux bugfix for Deb-based systems
# v2.6.2  2014-10-03 RCA change which/when files added to tarball, changes to tcpdump options
# v2.6.3  2014-10-31 RCA more addtions to tarball.
# v2.7    2014-11-03 RCA add --cleanup functionality, samba gathering, get-status detection of Unknown (lsass load delays), other minor issues.
# v2.7.1  2015-05-05 RCA fix crash due to "..." (python slip) if --gpo chosen
# v2.7.2  2015-06-18 RCA fix issue with tarFiles("/var/log/*")
# v2.8    2015-08-07 RCA gather additional information
# v2.9    2015-08-20 RCA basic memory statistics
# v2.9.3  2015-09-18 RCA add additional AIX and additional information to gather
# v2.10   2015-10-21 RCA add auto-detection of logfiles from syslog.conf/rsyslog.conf (no syslog-ng yet)
# v2.11   2015-12-16 RCA add --performance flag
# v2.11.1 2016-08-17 RCA add 8.5 and 8.6 detection and fix group policy testing with --gpagent and --gpo
# v2.12   2017-10-30 RCA fix logfile break on OSX
# v2.13   2018-09-28 RCA add alarm handling for runTool() so if commands time out, the script will continue.
# v2.14   2018-10-01 RCA add alarm handling for all calls to System() so if commands time out, the script will continue.
#
# Data structures explained at bottom of file
#
# TODO (some order of importance):
# Do pre-script cleanup (duplicate daemons, running tap-log, etc.)
# gather nscd information?
# gpo testing
# samba test / review
# edit lwiauthd and smb.conf for log level = 10 in [global] section properly
# do smbclient tests
# syslog-ng editing to allow non-restarts

use strict;
#use warnings;

use Getopt::Long;
use Cwd "abs_path";
use File::Basename;
use Carp;
use FindBin;
use Config;
use Sys::Hostname;
use sigtrap qw (handler cleanup old-interface-signals normal-signals);


# Define global variables
my $gVer = "2.14";
my $gDebug = 0;  #the system-wide log level. Off by default, changable by switch --loglevel
my $gOutput = \*STDOUT;
my $gRetval = 0; #used to determine exit status of program with bitmasks below:
my ($info, $opt);

# Define system signals
use Config;
my (%gSignals, @gSignalno); # Signame names, and signal numbers, respectively
defined $Config{sig_name} || die "No signals are available on this OS? That's not right!";
my $i = 0;
foreach my $name (split(' ', $Config{sig_name})) {
    $gSignals{$name} = $i;
    $gSignalno[$i] = $name;
    $i++;
}

# masking subs for applying to, and allowing us to return, $gRetval
sub ERR_UNKNOWN ()      { 1; }
sub ERR_OPTIONS ()      { 2; }
sub ERR_OS_INFO ()      { 2; }
sub ERR_ACCESS  ()      { 4; }
sub ERR_FILE_ACCESS ()  { 4; }
sub ERR_SYSTEM_CALL ()  { 8; }
sub ERR_DATA_INPUT  ()  { 16; }
sub ERR_LDAP        ()  { 32; }
sub ERR_NETWORK ()      { 64; }
sub ERR_CHOWN   ()      { 256; }
sub ERR_STAT    ()      { 512; }
sub ERR_MAP     ()      { 1024; }

sub main();
main();
exit $gRetval;

sub usage($$)
{
    my $opt = shift || confess "no options hash passed to usage!\n";
    my $info = shift || confess "no info hash passed to usage!\n";
    my $scriptName = fileparse($0);

    my $helplines = "
$scriptName version $gVer
(C)2008-2011, Likewise Software, 2011-2014 BeyondTrust Software

usage: $scriptName [tests] [log choices] [options]

This is the PBIS support tool.  It creates a log as specified by
the options, and creates a gzipped tarball in:
$opt->{tarballdir}/$opt->{tarballfile}$opt->{tarballext}, for emailing to
$info->{emailaddress}

Tests to be performed:

    --(no)ssh (default = ".&getOnOff($opt->{ssh}).")
        Test ssh logon interactively and gather logs
    --sshcommand <command> (default = '".$opt->{sshcommand}."')
    --sshuser <name> (instead of interactive prompt)
    --(no)gpo --grouppolicy (default = ".&getOnOff($opt->{gpo}).")
        Perform Group Policy tests and capture Group Policy cache
    -u --(no)users (default = ".&getOnOff($opt->{users}).")
        Enumerate all users
    -g --(no)groups (default = ".&getOnOff($opt->{groups}).")
        Enumerate all groups
    --autofs --(no)automounts (default = ".&getOnOff($opt->{automounts}).")
        Capture /etc/lwi_automount in tarball
    --(no)dns (default = ".&getOnOff($opt->{dns}).")
        DNS lookup tests
    -c --(no)tcpdump (--capture) (default = ".&getOnOff($opt->{tcpdump}).")
        Capture network traffic using OS default tool
        (tcpdump, nettl, snoop, etc.)
    --capturefile <file> (default = $opt->{capturefile})
    --captureiface <iface> (default = $opt->{captureiface})
    --(no)smb (default = ".&getOnOff($opt->{smb}).")
        run smbclient against local samba server
    -o --(no)othertests (--other) (default = ".&getOnOff($opt->{othertests}).")
        Pause to allow other tests (interactive logon,
        multiple ssh tests, etc.) to be run and logged.
    --(no)delay (default = ".&getOnOff($opt->{delay}).")
        Pause the script for $opt->{delaytime} seconds to gather logging
        data, for example from GUI logons.
    -m --memory (default = ".&getOnOff($opt->{memory}).")
        Gather memory utilization statistics to help find/disprove
        memory leaks.
    -p --performance (default = ".&getOnOff($opt->{performance}).")
        Run specific set of tests for performance troubleshooting
        of NSS modules and user lookups.
    -dt --delaytime <seconds> (default = $opt->{delaytime})
    -dj --domainjoin (default = ".&getOnOff($opt->{domainjoin}).")
        Set flags for attempting to join AD, then launch the join interactively
        --djcommand <command>
            command for domainjoin-cli, such as 'join', 'query', 'leave'
        --djoptions <options in quotes>
            Enter domainjoin args such as '--disable hostname --ou AZ/Phoenix/Server'
        --djdomain <domain>
            Name of domain to attempt to join
        --djlog (default = $opt->{djlog})
            Path of the domainjoin log.
        Use '--sshuser' for the domainjoin username, or be prompted

    Log choices:

    --(no)lsassd (--winbindd) (default = ".&getOnOff($opt->{lsassd}).")
        Gather lsassd debug logs
    --(no)lwiod (--lwrdrd | --npcmuxd) (default = ".&getOnOff($opt->{lwiod}).")
        Gather lwrdrd debug logs
    --(no)netlogond (default = ".&getOnOff($opt->{netlogond}).")
        Gather netlogond debug logs
    --(no)gpagentd (default = ".&getOnOff($opt->{gpagentd}).")
        Gather gpagentd debug logs
    --(no)eventlogd (default = ".&getOnOff($opt->{eventlogd}).")
        Gather eventlogd debug logs
    --(no)eventfwdd (default = ".&getOnOff($opt->{eventfwdd}).")
        Gather eventfwdd debug logs
    --(no)reapsysld (default = ".&getOnOff($opt->{reapsysld}).")
        Gather reapsysld debug logs
    --(no)regdaemon (default = ".&getOnOff($opt->{lwregd}).")
        Gather regdaemon debug logs
    --(no)lwsm (default = ".&getOnOff($opt->{lwsmd}).")
        Gather lwsm debug logs
    --(no)smartcard (default = ".&getOnOff($opt->{lwscd}).")
        Gather smartcard daemon debug logs
    --(no)certmgr (default = ".&getOnOff($opt->{lwcertd}).")
        Gather smartcard daemon debug logs
    --(no)autoenroll (default = ".&getOnOff($opt->{autoenrolld}).")
        Gather smartcard daemon debug logs
    --pbisloglevel (default = ".&getOnOff($opt->{pbislevel}).")
        What loglevel to run PBIS daemons at (useful for
        long-running captures).
    --(no)messages (default = ".&getOnOff($opt->{messages}).")
        Gather syslog logs
    --(no)gatherdb (default = ".&getOnOff($opt->{gatherdb}).")
        Gather PBIS Databases
    --(no)sambalogs (default = ".&getOnOff($opt->{sambalogs}).")
        Gather logs and config for Samba server
    -ps --(no)psoutput (default = ".&getOnOff($opt->{psoutput}).")
        Gathers full process list from this system
    -m --memory (default = ".&getOnOff($opt->{memory}).")

    Options:

    -r --(no)restart (default = ".&getOnOff($opt->{restart}).")
        Allow restart of the PBIS daemons to separate logs
    --(no)syslog (default = ".&getOnOff($opt->{syslog}).")
        Allow editing syslog.conf during the debug run if not
        restarting daemons (exclusive of -r)
    -V --loglevel {error,warning,info,verbose,debug}
        Changes this tool's logging level. (default = $opt->{loglevel} )
    -l --log --logfile <path> (default = $opt->{logfile} )
        Choose the logfile to write data to.
    -t --tarballdir <path> (default = $opt->{tarballdir} )
        Choose where to create the gzipped tarball of log data
    --alarm <seconds> (default = $opt->{alarmtime} )
        How long to allow tasks to run before they time out
        (sometimes enumerating users or groups can take 10 minutes)

Examples:

$scriptName --ssh --lsassd --nomessages --restart -l pbis.log
$scriptName --restart --regdaemon -c
    Capture a tcpdump or snoop of all daemons starting up
    as well as full logs

";
    #    --cleanup (default = ".&getOnOff($opt->{cleanup}).")
    #        Run cleanup routines if tool gets cancelled in the middle
    #        of running.
    #        Will generate a tarball of output.
    return $helplines;
}

######################################
# Helper Functions Defined Below
#
# Used as shortcuts throughout the
# other subroutines, or called in
# multiple "main" routines, or
# just planned to be reused

sub cleanup {
    logData("");
    logError("Recieved CTRL-C, cleaning up...!");
    logData("");
    if ($info->{scriptstatus}->{tcpdump}) {
        tcpdumpStop($info, $opt);
    }
    if ($info->{scriptstatus}->{loglevel}) {
        changeLoggingLevels($info, $opt, "normal");
        if ($opt->{restart} and $info->{lw}->{control} eq "lwsm") {
            runTool($info, $opt, "lwsm autostart", "print");
        }
    }
    $gRetval |= ERR_SYSTEM_CALL;
    logError("exiting for CTRL-C.");
    exit $gRetval;
}

sub daemonRestart($$) {
    my $info = shift || confess "no info hash to restartDaemon!!\n";
    my $options = shift || confess "no options hash to restartDaemon!!\n";
    my ($startscript, $logopts, $result);
    logInfo("Stopping $options->{daemon}...");

    if ($info->{$options->{daemon}}->{pid}) {
        # script was started manually (not via startups script)
        # cause we don't store the pid when starting via init script
        logInfo("killing process $options->{daemon} by pid $info->{$options->{daemon}}->{pid}");
        $result = killProc($info->{$options->{daemon}}->{pid}, 15, $info);
        if ($options->{daemon}=~/^lwsm/) {
            logInfo("Sleeping 30 seconds for $options->{daemon} to safely stop");
            sleep 30;
        }
        my $procpid = findProcess($options->{daemon}, $info);
        $result = ERR_SYSTEM_CALL if (defined($procpid->{pid}));
        if ($result & ERR_SYSTEM_CALL) {
            logVerbose("Failed kill by ID, trying by name $options->{daemon}");
            $result = killProc("$options->{daemon}", 9, $info);
            if ($result & ERR_SYSTEM_CALL) {
                logError("Couldn't stop or kill $options->{daemon}");
                logError("Manually stop or kill $options->{daemon} or it will continue running with debugging on.");
                $gRetval|=ERR_SYSTEM_CALL;
            }
        }
    } else {
        # Build the startscript based on hash data, then replace the generic "daemonname"
        # with the proper value.
        $startscript = $info->{svcctl}->{stop1}.$info->{svcctl}->{stop2}.$info->{svcctl}->{stop3};
        $startscript =~ s/daemonname/$options->{daemon}/;
        logDebug("Calling $options->{daemon} stop as: ".$startscript);
        $result = System("$startscript", undef, $opt->{alarmtime}); #removed for Mac Stpuidness:  > /dev/null 2>&1"); #2011-04-12 RCA
        if ($options->{daemon}=~/^lwsm/) {
            logInfo("Sleeping 30 seconds for $options->{daemon} to safely stop");
            sleep 30;
        } else {
            sleep 1;
        }

        my $proc=findProcess($options->{daemon}, $info);
        if (($info->{OStype} eq "darwin") and defined($proc->{pid})) {
            $result = System("$startscript > /dev/null 2>&1", undef, $opt->{alarmtime});
            # Darwin 10.6 seems to need 2 "launchctl stop" commands in testing - 2011-04-12 RCA
            sleep 2;
        }
        $proc=findProcess($options->{daemon}, $info) if ($info->{OStype} eq "darwin");
        if ($result || ($info->{OStype} eq "darwin")) {
            logWarning("Process $options->{daemon} failed to stop, attempting kill");
            if (defined($info->{$options->{daemon}}->{pid})) {
                logVerbose("killing process $options->{daemon} by pid $info->{$options->{daemon}}->{pid}");
                $result = killProc($info->{$options->{daemon}}->{pid}, 9, $info);
            } else {
                logVerbose("killing process $options->{daemon} with pkill");
                $result = killProc($options->{daemon}, 9, $info);
            }
            if ($result) {
                $gRetval |= ERR_SYSTEM_CALL;
                logError("Couldn't stop or kill $options->{daemon}");
            }
        } else {
            logVerbose("Successfully stopped $options->{daemon}");
        }
    }
    # make sure it's really down, else recursively try again
    my $catch;
    for my $i (1 .. 10) {
        sleep 2;
        $catch = findProcess($options->{daemon}, $info);
        last if (not defined($catch->{pid}));
        killProc($options->{daemon}, 15, $info);
        my $j=10-$i;
        logVerbose("$options->{daemon} failed to stop, doing last-ditch kill (".$j." attempts)...")
    }
    killProc($options->{daemon}, 9, $info) if defined($catch->{pid});
    sleep 5;
    # now we start the daemon back up
    if (not defined($options->{loglevel}) or $options->{loglevel} eq "normal") {
        #restart using init scripts, no special logging
        logInfo("Starting $options->{daemon}...");
        $startscript = $info->{svcctl}->{start1}.$info->{svcctl}->{start2}.$info->{svcctl}->{start3};
        $startscript =~ s/daemonname/$options->{daemon}/;
        logDebug("Calling $options->{daemon} start as: '$startscript'");
        $result = System("$startscript", undef, $opt->{alarmtime}); # removed for Mac stupidness:  > /dev/null 2>&1");
        if ($result) {
            $gRetval |= ERR_SYSTEM_CALL;
            logError("Failed to start $options->{daemon}");
            logError("System may be in an unusable state!!");
        } else {
            logDebug("Successfully started $options->{daemon}");
        }
    } else {
        $logopts = " --loglevel $options->{loglevel} --logfile ".$info->{logpath}."/".$options->{daemon}.".log ".$info->{lw}->{daemons}->{startcmd};
        $startscript = $info->{lw}->{base}."/sbin/".$options->{daemon}.$logopts;
        logInfo("Starting $options->{daemon} as: $startscript");
        #TODO replace with proper forking
        $result = open($info->{$options->{daemon}}->{handle}, "$startscript > /dev/null|");
        if ($result) {
            my $proc=findProcess($options->{daemon}, $info);
            $info->{$options->{daemon}}->{pid} = $proc->{pid};
            logVerbose("pid for $options->{daemon} = $proc->{pid}");
        } else {
            $gRetval |= ERR_SYSTEM_CALL;
            logError("Failed to start $options->{daemon}");
            logError("System may be in an unusable state!!");
        }
    }
    return;
}

sub daemonContainerStop($$) {
    my $info = shift || confess "no info hash to daemonContainerStop!!\n";
    my $options = shift || confess "no options hash to daemonContainerStop!!\n";
    my ($result, $script);
    logInfo("Stopping $options->{daemon}...");
    my $proc=findProcess($options->{daemon}, $info);
    if ($proc) {
        $script=$info->{lw}->{path}."/".$info->{lwsm}->{control}." stop ".$options->{daemon};
        logVerbose("Running: $script");
        $result = System("$script", undef, $opt->{alarmtime});
    }
    if (defined($info->{$options->{daemon}}->{pid}) and $info->{$options->{daemon}}->{pid}) {
        logWarning("$options->{daemon} failed to stop, killing process by stored pid $info->{$options->{daemon}}->{pid}");
        $result = killProc($info->{$options->{daemon}}->{pid}, 9, $info);
    }
    $proc=findProcess($options->{daemon}, $info);
    if (exists $proc->{pid}) {
        logWarning("$options->{daemon} failed to stop, killing process by found pid $proc->{pid}!");
        $result = killProc($proc->{pid}, 9, $info);
        if ($result) {
            logError("Failed to stop $options->{daemon} - this system is in an unusable state!");
            $gRetval |= ERR_SYSTEM_CALL;
            return $gRetval;
        }
    } else {
        logVerbose("$options->{daemon} not found to be running (probably ok)");
    }
    if (exists $info->{$options->{daemon}}->{pid}) {
        delete $info->{$options->{daemon}}->{pid};
        #        I don't think I have handles in use in this portion of the code. But if they are, here's how to clean them up.
        #        close $info->{$options->{daemon}}->{handle};
        #        delete $info->{$options->{daemon}}->{handle};
        logVerbose("Clearing pid for $options->{daemon}");
    }
    return $result;
}

sub daemonContainerStart($$) {
    my $info = shift || confess "no info hash to daemonContainerStart!!\n";
    my $options = shift || confess "no options hash to daemonContainerStart!!\n";
    my ($startscript, $logopts, $result);
    if ($info->{$options->{daemon}}->{pid}) {
        logWarning("daemonContainerStart was called with an already valid PID for $options->{daemon}, killing it.");
        daemonContainerStop($info, $options);
    }
    if (not ($options->{loglevel} eq "normal") and defined ($options->{loglevel})) {
        $startscript = $info->{lw}->{base}."/sbin/".$info->{lw}->{daemons}->{lwsm}."d --container ";
        $startscript = $startscript.$options->{daemon}." ";
        $startscript = $startscript."--loglevel $options->{loglevel} ";
        $startscript = $startscript."--logfile ".$info->{logpath}."/".$options->{daemon}.".log";
        logInfo("Starting container $startscript...");
        $result = System("$startscript &", undef, $opt->{alarmtime});
        if (not $result) {
            my $proc=findProcess($options->{daemon}, $info);
            $info->{$options->{daemon}}->{pid} = $proc->{pid};
            logVerbose("pid for $options->{daemon} = $proc->{pid}");
        } else {
            $gRetval |= ERR_SYSTEM_CALL;
            logError("Failed to start container $startscript!");
            logError("System may be in an unusable state!!");
        }
    }
    $startscript = $info->{lw}->{path}."/".$info->{lwsm}->{control}." start ".$options->{daemon};
    logVerbose("Running: $startscript");
    $result = System($startscript, undef, $opt->{alarmtime});
    if ($result) {
        logError("Failed to start daemon $options->{daemon} via lwsm!");
        $gRetval |= ERR_SYSTEM_CALL;
        return $gRetval;
    }
    return $result;
}

sub dnsLookup($$) {
    my $query = shift || confess "No name to lookup passed to dnsSrvLookup()!";
    my $type = shift || confess "No Query Type passed to dnsLookup()!";
    my @results;

    my $lookup = {};
    foreach (("dig", "nslookup")) {
        $lookup = findInPath("dig", ["/sbin", "/usr/sbin", "/bin", "/usr/bin", "/usr/local/sbin", "/usr/local/bin"]);
        last if ($lookup->{path} and ($lookup->{perm}=~/x/));
    }
    unless ($lookup->{path}) {
        $gRetval |= ERR_FILE_ACCESS;
        logError("Could not find 'dig' or 'nslookup' - unable to do any network tests!");
        return;
    }
    if ($lookup->{name} eq "dig") {
        logVerbose("Performing DNS dig: '$lookup->{path} $type $query'.");
        open(NS, "$lookup->{path} $type $query |");
        while (<NS>) {
            next if (/^;/);
            next if (/^\s*$/);
            push(@results, $_);
        }
        close NS;

    } elsif ($lookup->{name} eq "nslookup") {
        my $line="";
        logVerbose("Performing DNS nslookup: '$lookup->{path} -query=$type $query'.");
        open(NS, "$lookup->{path} -query=$type $query |");
        while (<NS>) {
            chomp;
            my ($p1, $p2) = split(/\s+/, $_, 2);
            if ($p1 =~ /Name:/) {
                $line=$p2;
                logDebug("Matched a server name in nslookup: $p2");
            }
            if ($p1 =~ /Address:/ and $line) {
                push(@results, $line."     $p2");
                logDebug("Matched a server address in nslookup: $line is $p2");
                $line="";
            }
        }
    }
    return @results;
}
sub dnsSrvLookup($) {
    my $query = shift || confess "No name to lookup passed to dnsSrvLookup()!";

    my @records;
    logVerbose("Performing DNS lookup: 'dnsLookup() SRV $query'.");
    my @dclist = dnsLookup($query, "SRV");
    foreach my $dc (@dclist) {
        next unless ($dc =~ /^$query\./);
        logDebug("Looking at DNS Record: $dc");
        $dc =~ /([^\s]+)\.$/;
        push(@records, $1); # if ($1 =~ /^[a-zA-Z0-9\-\.]$/);
    }

    foreach (@records) {
        logVerbose("Returning '$_'");
    }
    return @records;
}

sub findLogFile {
    my $facility=shift;
    $facility="daemon" if ($facility eq "*");  #have to escape the star for later regex searches
    $facility="($facility|\\*)";
    my $syslog;
    my @files;
    my $file="";
    foreach my $candidate (("syslog-ng.conf", "rsyslog.conf", "syslog.conf")) {
        $syslog=findInPath($candidate, ["/etc/", "/usr/local/etc/", "/opt/etc", "/etc/local"]);
        if ($syslog->{path}) {
            logVerbose("Found $candidate in path $syslog->{dir}!");
            last;
        }
    }
    # rsyslog and syslog-ng can include ".d/*.conf" files as well, so we need to read in *everything*
    my @paths=($syslog->{path});
    PATH: foreach my $path (@paths) {
        if (open(my $sl, "<$path")) {
            READ: while(<$sl>) {
                chomp;
                next if ($_=~/^\s*#/);  #skip comments
                next if ($_=~/^\s*$/);  #skip blank lines
                next if ($_=~/syslog-reaper/); #skip PBIS syslog-reaper lines, since we can't include them
                next if ($_=~/^\s*\$Mod/); # skip ModLoad in rsyslog
                logDebug("Reading $path line: $_");
                if ($_=~/^\s*\$IncludeConfig\s*(.*)/) {
                    my @newpaths=glob $1; #do this so we can print, rather than just adding to @paths directly.
                    logVerbose("Adding paths: ".join(" ", @newpaths)."; to syslog path search.");
                    push(@paths, @newpaths);
                    next;
                }
                if ($_=~/(^|\b)$facility(\.|,[^.]+.)(\*|err|crit|notice|warn|info|verbose|debug)(;[^\s]+)?\s+-?([^\s]+)/) {
                    $file=$6;
                    logVerbose("Matched $file for $facility.");
                    if ( -f "$file" ) {
                        push(@files, $file);
                        # we have our match, and $file is scoped to the sub.
                    } else {
                        logVerbose("Matched $file for $facility, but it's not a file, continuing.");
                    }
                }
                if ($_=~/\{/) {
                    #dirty check for syslog-ng
                    logError("Syslog-ng found, can't handle that right now!!!");
                    #TODO syslog-ng, obvs.
                }
            }
        } else {
            $gRetval|= ERR_ACCESS;
            logError("Can't open $path for reading!");
            next;
        };
        logVerbose("Didn't find $facility in $path.");
    }
    if (not @files) {
        logError("Couldn't find $facility in any syslog files! returning empty logfile.");
    }
    return @files;
}

sub findProcess($$) {
    my $process = shift;
    my $info=shift;
    my $proc={};
    $process=safeRegex($process);

    if (not ($process =~/^\d+$/)) {
        logDebug("Passed $process by name, figuring out its PID...");
        my @lines;
        open(PS, "$info->{pscmd}|");
        my $catch;
        while (<PS>) {
            chomp;
            $_=~s/^\s*//;
            $_=~s/\s*$//;
            if ($_ =~/$process/i) {
                logDebug("Found possible match in line: $_");
                my @els = split(/\s+/, $_);
                $catch = $els[1];
                if ($els[7]=~/^[0-9:]*$/) {
                    #long-running processes mean that "STIME" may have a space in it;
                    $proc->{cmd}=$els[8];
                } else {
                    $proc->{cmd} = $els[7];
                }
                if ($proc->{cmd} =~ /(lw-container|lwsm)/) {
                    $proc->{cmd} = join(" ", @els[7..$#els]);
                }
                logDebug("Checking '$proc->{cmd}' for /$process/.");
                unless ($proc->{cmd} =~ /$process/) {
                    undef $catch;
                    $proc={};
                }
            }
            last if $catch;
        }
        close PS;
        if ($catch) {
            logVerbose("Found $process with pid $catch.");
            $proc->{pid} = $catch;
            $proc->{bin} = $process;
        } else {
            logVerbose("Didn't find $process running.");
            return {};
        }
    } else {
        my @lines;
        open(PS, "$info->{pscmd}|");
        my $catch;
        while (<PS>) {
            chomp;
            $_=~s/^\s*//;
            $_=~s/\s*$//;
            logDebug("ps line: $_");
            my @els = split(/\s+/, $_);
            if ($els[1] eq $process) {
                $catch = $els[1];
                $proc->{cmd} = $els[7];
            }
            last if $catch;
        }
        close PS;
        if ($catch) {
            logVerbose("Found $process with pid $catch.");
            $proc->{pid} = $catch;
            $proc->{cmd} =~/\/(\w+)(\s|$)/;
            $proc->{bin} = $1;
        } else {
            logVerbose("Didn't find $process running.");
            return {};
        }
    }
    return $proc;
}

sub GetErrorCodeFromChildError($)
{
    my $error = shift;

    if ($error == -1)
    {
        return $error;
    }
    else
    {
        return $error >> 8;
    }
}

sub getOnOff($) {
    # returns pretty "on/off" status for the default values
    # for the help screen.
    my $test = shift;
    if ($test) {
        return $test if ($test=~/../ || $test > 1);
        return "on";
    } else {
        return "off";
    }
}

sub getUserInfo($$$) {
    my $info = shift || confess "no info hash passed to getUserInfo!!\n";
    my $opt = shift || confess "no options hash passed to getUserInfo!!\n";
    my $name = shift;
    my ($data, $error);
    if (not defined($name)) {
        if (not defined($info->{name})) {
            logError("No username passed for user info lookup!");
            $gRetval |= ERR_DATA_INPUT;
            return $gRetval;
        } else {
            $name=$info->{name};
        }
    }
    logData("getent passwd $name: ");
    logData(join(":", getpwnam($name)));
    logData("");
    if ($info->{OStype} eq "aix") {
        runTool($info, $opt, "/usr/sbin/lsuser -f '$name'", "print");
    }
    return 0 if ($name=~/^root$/i);  #no need to do AD lookups for root
    logData("PBIS direct lookup:");
    runTool($info, $opt, "$info->{lw}->{tools}->{userbyname} '$name'", "print");
    logData("User Group Membership:");
    runTool($info, $opt, "$info->{lw}->{tools}->{groupsforuser} '$name'", "print");

    return 0;
}

sub findInPath($$) {
    # finds a particular file in a path
    # (filename,pathArrayReference) expected input
    # does an lstat, so returns info from the lstat as well for convenience
    # returns ref to hash:
    # hash->{path} = path to file
    # hash->{type} = file type (file, directory, executable, etc.)
    # hash->{info} = ref to info{} hash from lstat
    # if file not found, return $file with undef $file->{path}

    my $filename = shift || confess "ERROR: no filename passed for path search!\n";
    my $paths = shift || confess "ERROR: no paths passed to search for $filename!\n";
    my $file = {};

    foreach my $path (@$paths) {
        if (-e "$path/$filename") {
            $file->{info} = stat(_);
            $file->{perm} = "";
            $file->{path} = "$path/$filename";
            $file->{type} = "d" if (-d _);
            $file->{type} = "f" if (-f _);
            $file->{type} = "c" if (-c _);
            $file->{perm} .= "r" if (-r _);
            $file->{perm} .= "x" if (-x _);
            $file->{perm} .= "w" if (-w _);
            $file->{name} = $filename;
            $file->{dir} = $path;
            last;
        }
    }
    if (not defined($file->{path})) {
        $file->{info} = [];
    }
    return $file;
}

sub lineDelete($$) {
    my $file = shift || confess "ERROR: No file hash to delete line from!\n";
    my $line = shift || confess "ERROR: no line to delete from $file!\n";
    my $error;
    if ($file->{perm}!~/w/) {
        $gRetval |= ERR_FILE_ACCESS;
        logError("could not read from $file->{path} to see if '$line' already exists");
        return $gRetval;
    }
    $error = "";
    my $data;
    {
        local @ARGV=($file->{path});
        local $^I = '.lwd'; # <-- turns on inplace editing (d for delete)
        my $regex = safeRegex($line);
        while (<>) {
            if (/^[#;]+\s*$regex/) {
                $data = "Found '$line' commented out in $file->{path}, leaving alone.";
                print;
            } elsif (s/^\s*$regex/#    $line/) {
                $data = "Found '$line' in $file->{path}, commenting out.";
                $error = "found";
                print;
            } else {
                print;
            }
        }
    }
    logDebug($data) if ($data);
    if (defined($error) && $error ne "found") {
        logInfo("Could not find '$line' in $file->{path}.");
    }
}

sub lineInsert($$) {
    my $file = shift || confess "ERROR: No file hash to insert line into!\n";
    my $line = shift || confess "ERROR: no line to insert into $file!\n";
    my $error;
    if ($file->{perm}!~/w/) {
        $gRetval |= ERR_FILE_ACCESS;
        logError("could not read from $file->{path} to see if '$line' already exists");
        return $gRetval;
    }
    $error = "";
    my $data;
    {
        local @ARGV=($file->{path});
        local $^I = '.lwi'; # <-- turns on inplace editing (i for insert)
        my $regex = safeRegex($line);
        while (<>) {
            if (s/^[#;]+\s*$regex/$line/) {
                $error = "found";
                $data ="Found line '$line' commented out in $file->{path}, removing comments";
                print;
            } elsif (/^\s*$regex/) {
                $error = "found";
                $data = "Found line '$line' in $file->{path}, leaving it alone";
                print;
            } else {
                print;
            }
        }
    }
    logDebug($data) if ($data);
    if (defined($error) && $error ne "found") {
        open(FH, ">>$file->{path}");
        $error = print FH "$line\n";
        unless ($error) {
            $gRetval |= ERR_FILE_ACCESS;
            logError("Could not append $line to $file->{path} - $error - $!\n");
        }
        close FH;
    }
}

sub logData($) {
    my $line = shift;
    logger(1, $line);
}

sub logError($) {
    my $line = shift;
    $line = "ERROR: ".$line;
    my $error = 0;
    $error = print STDERR "$line\n";
    $gRetval |= ERR_FILE_ACCESS unless $error;
    logger(1, $line);
}

sub logWarning($) {
    my $line = shift;
    $line = "WARNING: ".$line;
    logger(2, $line);
}

sub logInfo($) {
    my $line = shift;
    $line = "INFO: ".$line;
    logger(3, $line);
}

sub logVerbose($) {
    my $line = shift;
    $line = "VERBOSE: ".$line;
    logger(4, $line);
}

sub logDebug($) {
    my $line = shift;
    $line = "DEBUG: ".$line;
    logger(5, $line);
}

sub logger($$) {
    # Writes to the global $gOutput file handle
    # handles errors with $gRetval
    # can be called directly, but it's better to call the error
    # handlers above, logError, logWarning, logData, etc.

    my $level = shift ||confess "ERROR: No verbosity level passed to logger!\n";
    my $line = shift; # now ok to pass empty line to logger ||confess "ERROR: No line to log passed to logger!\n";

    return $gRetval if ($level>$gDebug);

    $line = " " if (not defined($line));

    my $error = 0;
    chomp $line;
    $error = print $gOutput "$line\n";
    $gRetval |= ERR_FILE_ACCESS unless $error;
    if ($gOutput != \*STDOUT ) {
        print "$line\n";
    }
    return $gRetval;
}

sub killProc($$$) {
    my $process = shift || confess "ERROR: no process to kill!\n";
    my $signal = shift || confess "ERROR: No signal to send to $process!\n";
    my $info = shift || confess "ERROR: No info hash!\n";

    my $proc=findProcess($process, $info);

    if (defined($proc->{pid}) && $proc->{pid}=~/^\d+$/) {
        logInfo("Found $process with pid $proc->{pid}.");
    } else {
        logError("Could not pkill $process - it does not appear to be running!");
        return ERR_SYSTEM_CALL();
    }

    my $error;
    if ($signal == 9 || $signal=~/kill/i) {
        logInfo("Attempting to kill PID $process with signal 15");
        $error = killProc2(15, $proc);
        if ($error) {
            logWarning("$process did not respond to SIGTERM, having to send KILL");
            $error = killProc2(9, $proc);
            if ($error) {
                return $error;
            } else {
                logInfo("Successfully killed hung process $proc->{pid}");
                return 0;
            }
        } else {
            logVerbose("Successfully terminated PID $process");
            return 0;
        }
    } else {
        logVerbose("Attemping to kill PID $process with signal $signal");
        $error = killProc2($signal, $proc);
        return $error;
    }
}

sub killProc2($$) {
    my $signal = shift || confess "ERROR: No signal to kill process with!";
    my $proc = shift || confess "ERROR: No process to kill!";
    my $process = $proc->{pid};
    my $safesig;
    unless ($process=~/^\d+$/) {
        logError("$process is not a numeric PID, so we cannot kill it!");
        return ERR_OPTIONS;
    }
    foreach my $sig (sort(keys(%gSignals))) {
        if ($signal eq $sig) {
            $safesig = $signal;
            # just making sure that the signal being asked to be sent is on the list of available signals
            last;
        }
    }
    unless ($safesig or $signal=~/^\d+$/ or $signal > ($#gSignalno + 1)) {
        logError("$signal is unknown, so can't send it to $process!");
        return ERR_OPTIONS;
    }
    my $error = kill($signal, $process);
    unless ($error) {
        # kill returns number of processes killed.
        logError("Could not kill PID $process with signal $signal - $!");
        return ERR_SYSTEM_CALL;
    } else {
        logVerbose("successfully killed $error processes");
        return 0;
    }
}

sub readFile($$) {
    my $info = shift || confess "no info hash passed to readFile!";
    my $filename = shift || confess "no filename passed to readFile!";

    $filename =~/^(.*)[\/]([^\/]+)$/;

    my $file = findInPath($2, ["$1"]);
    if (defined($file->{path})) {
        my $error = open(SV, "<$file->{path}");
        unless ($error) {
            $gRetval |= ERR_FILE_ACCESS;
            logError("Can't open $file->{path}");
            return $gRetval;
        } else {
            while (<SV>) {
                logData($_);
            }
            close SV;
        }
    }
    return 0;

}

sub runTool($$$$;$) {
    my $info = shift || confess "no info hash passed to runTool!\n";
    my $opt = shift || confess "no opt hash passed to runTool!\n";
    my $tool = shift || confess "no tool to run passed to runTool!\n";
    my $action = shift || confess "no action passed to runTool!\n";
    my $filter = shift;
    # available actions:
    #  bury (throws output away, useful for actually *doing* something, actually not memory-safe, since we store the output in case of error)
    #  print (logs each line to the log as it comes up, memory-safe)
    #  grep (greps each line for $filter, returns as a string. not memory-safe)
    #  return (default, returns the lines as a string, not memory-safe)

    my $cmd="";
    my $data="";
    if (! -x $tool) {
        my @parts=split(/\s+/, $tool);
        my @search=split(/:/, $ENV{PATH});
        my $hash=findInPath($parts[0], \@search);
        logVerbose("Couldn't find '$tool' executable, trying to find it as '$parts[0]'.");
        if ( -x "$info->{lw}->{path}/$parts[0]") {
            $cmd = "$info->{lw}->{path}/$tool 2>&1";
        } elsif (defined($hash->{path})) {
            logDebug("Found $parts[0] in $hash->{dir}, building fullpath for program back up...");
            $cmd="$hash->{dir}/$tool 2>&1";
        } else {
            logDebug("Looks like $parts[0] is a shell builtin, so we'll shell to bash -c...");
            $tool=~s/([^[:alnum:]_\-\$])/\\$1/g;  #take a trick from sudo code
            $cmd="sh -c $tool 2>&1";
        }
    } else {
        $cmd = "$tool 2>&1";
    }
    logVerbose("Attempting to run '$cmd'");
    my $ret = "";
    my $alarmtimeout=$opt->{alarmtime};
    logInfo("Setting alarm timeout to $alarmtimeout.");
    {
        # disable alarm to prevent possible race condition between end of eval and execution of alarm(0) after eval
        local $SIG{ALRM} = sub { };
        $ret = eval {
            local $SIG{ALRM} = sub { die $data };
            alarm($alarmtimeout);
            if ($action eq "bury") {
                $data=`$cmd 2>&1`;
                $data="" unless ($?);
            } elsif ($action eq "print") {
                if (open(my $RT, "$cmd |")) {
                    while (<$RT>) {
                        logData("$_");
                    }
                    close RT;
                } else {
                    logError("Could not run '$cmd'!");
                }
                $data="";
            } elsif ($action eq "grep") {
                if (open(RT, "$cmd | ")) {
                    my @results;
                    while (<RT>) {
                        if ($_=~/$filter/) {
                            if ($1) {
                                push(@results, $1);
                            } else {
                                push(@results, $_);
                            }
                        }
                    }
                    close RT;
                    $data=join("\n", @results);
                } else {
                    $data="";
                    logError("Could not run '$cmd' to grep for '$filter'!!");
                }
            } else { # ($action eq "return")
                $data=`$cmd`;
            }
            if ($?) {
                $gRetval |= ERR_SYSTEM_CALL;
                logError("Error running $tool!");
                logInfo("$data");
                $data = "";
            };
            $data;
        };
        alarm(0);
    };
    return $data;
}

sub safeRegex($) {
    my $line = shift || confess "no line to clean up for regex matching!\n";
    my $regex = $line;
    $regex=~s/([\*\[\]\-\(\)\.\?\/\^\\])/\\$1/g;
    logDebug("Cleaned up '$line' as '$regex'");
    return $regex;
}

sub safeUsername($) {
    my $name = shift || confess "No username to clean up!!\n";
    my $cleaned = $name;
    $cleaned=~s/\\\\/\\/g;
    $cleaned=~s/(\$\*\{\})/\\$1/g;
    $cleaned="$cleaned";
    logDebug("Cleaned up $name as $cleaned");
    return $cleaned;
}

sub sectionBreak($) {
    my $title = shift || confess "no title to print section break to!\n";
    logData(" ");
    logData("############################################");
    logData("# Section $title");
    logData("# ".scalar(localtime()));
    logData("# ");
    return 0;
}

sub System($;$$)
{
    my $command = shift || confess "No Command to launch passed to System!\n";
    my $print = shift;
    my $timeout = shift;

    if (defined($print) && $print=~/^\d+$/) {
        logDebug("RUN: $command");
    }
    if ($timeout) {
        my $pid = fork();
        if (not defined $pid) {
            logError("FORK failed for: $command");
            return 1;
        }
        if (not $pid) {
            exec("$command");
            exit($?);
        } else {
            my $rc;
            eval {
                local $SIG{ALRM} = sub { logError("ALARM: process timeout"); };
                alarm($timeout);
                my $child = waitpid($pid, 0);
                if ($child >= 0) {
                    $rc = GetErrorCodeFromChildError($?);
                } else {
                    $rc = 1;
                }
                alarm(0);
            };
            if ($@) {
                if ($@ =~ /ALARM: process timeout/) {
                    logError("\n*** PROCESS TIMED OUT ***\n");
                    killProc2(9, $pid);
                    $rc = 1;
                } else {
                    confess;
                }
            }
            return $rc;
        }
    } else {
        system("nohup $command");
        return GetErrorCodeFromChildError($?);
    }
}

sub tarFiles($$$$) {
    my $info = shift || confess "no info hash passed to tar appender!\n";
    my $opt = shift || confess "no options hash passed to tar appender!\n";
    my $tar = shift || confess "no tar file passed to tar appender!\n";
    my $file = shift || confess "no append file passed to tar appender!\n";

    if ($file=~/\*[^\/]*$/) {
        # askign for /path/to/files/*
        my $dir=$file;
        $dir=~s|/[^/]*$||;
        if (! -d $dir ){
            logWarning("Not adding $file to $tar - $dir doesn't exist!");
            return;
        }
    } elsif (! -e $file) {
        logWarning("Not adding $file to $tar - $file doesn't exist");
        return;
    } elsif ( -l $file ) {
        #we want the actual contents, not just the link
        logInfo("$file is a link, adding its target first.");
        tarFiles($info, $opt, $tar, abs_path($file));
    } else {
        logVerbose("No errors looking for existance of $file, continuing.");
    }

    logInfo("Adding file $file to $tar");
    my $error;
    if (-e $tar) {
        $error = System("tar -rf $tar $file > /dev/null 2>&1", undef, $opt->{alarmtime});
    } else {
        $error = System("tar -cf $tar $file > /dev/null 2>&1", undef, $opt->{alarmtime});
    }
    if ($error) {
        $gRetval |= ERR_SYSTEM_CALL;
        logError("Error $error adding $file to $tar - $!");
    }
}

sub tcpdumpStart($$) {
    my $info = shift || confess "No info hash passed to tcpdump()!\n";
    my $opt = shift || confess "No options hash passed to tcpdump()!\n";
    my $iface="";

    logInfo("starting tcpdump analogue for $info->{OStype}");
    if ($opt->{captureiface}) {
        $iface=$info->{tcpdump}->{ifaceflag}.$opt->{captureiface};
    }
    my $dumpcmd = "$info->{tcpdump}->{startcmd} $iface $info->{tcpdump}->{args} $opt->{capturefile} $info->{tcpdump}->{filter}";
    logVerbose("Trying to run: $dumpcmd");
    my $error = System("$dumpcmd &", undef, $opt->{alarmtime});
    if ($error) {
        $gRetval |= ERR_SYSTEM_CALL;
        logError("Could not start capture command: $dumpcmd");
    }
}

sub tcpdumpStop($$) {
    my $info = shift || confess "No info hash passed to tcpdump()!\n";
    my $opt = shift || confess "No options hash passed to tcpdump()!\n";

    logInfo("Stopping tcpdump analogue for $info->{OStype}");
    my $error;
    my $stopcmd = "$info->{tcpdump}->{stopcmd}";
    if ($stopcmd eq "kill") {
        logVerbose("Stopping tcpdump by killing it...");
        $error = killProc("$info->{tcpdump}->{startcmd}", 9, $info);
    } else {
        logVerbose("Sending stop command...");
        my $error = System($stopcmd, undef, $opt->{alarmtime});
        if ($error) {
            logWarning("There was an error running: '$stopcmd', trying to kill via kill -9.");
            $error=killProc($info->{tcpdump}->{startcmd}, 9, $info);
        }
    }
    if ($error) {
        logError("Unable to kill capture command via '$stopcmd' or via kill -9! It may still be running!");
        $gRetval |= ERR_SYSTEM_CALL;
    }
}

# Helper Functions End
#####################################

#####################################
# Main Functions Below

sub changeLogging($$$) {
    my $info = shift || confess "no info hash passed to log starter!\n";
    my $opt = shift || confess "no options hash passed to log starter!\n";
    my $state = shift || confess "no start/stop state passed to log start!\n";
    logDebug("Determining restart ability");
    if ($opt->{restart} && $info->{uid} == 0) {
        logDebug("requested to restart daemons, beginning.");
        my $options = { daemon => "",
            loglevel => "$state",
        };
        if ($info->{lwsm}->{control} eq "lwsm") {
            if ($info->{lwsm}->{type} eq "standalone") {
                logVerbose("Restarting standalone daemons inside lwsm.");
                changeLoggingWithLwSm($info, $opt, $options);
            } elsif ($info->{lwsm}->{type} eq "container") {
                logVerbose("Restarting containerized daemons inside lwsm");
                changeLoggingWithContainer($info, $opt, $options);
            }
            return;
        } else {
            logVerbose("Restarting standalone daemons.");
            changeLoggingStandAlone($info, $opt, $options);
            return;
        }
    } else {
        if ($info->{uid} != 0) {
            logError("can't restart daemons or make syslog.conf changes");
            logError("This tool needs to be run as root for these options");
            $gRetval |= ERR_SYSTEM_CALL;
            return;
        }
        if ($info->{lwsm}->{type} eq "container") {
            logVerbose("Setting up tap-log log captures.");
            changeLoggingByTap($info, $opt, $state);
            return;
        } else {
            logVerbose("Setting up syslog.conf edited log captures.");
            changeLoggingBySyslog($info, $opt, $state);
            return;
        }
    }

    return;
}

sub changeLoggingByTap($$$) {
    my $info = shift || confess "no info hash passed to log starter!\n";
    my $opt = shift || confess "no options hash passed to log starter!\n";
    my $state = shift || confess "no start/stop state passed to log start!\n";
    my $error;
    $opt->{paclog} = "$info->{logpath}/lsass.log" if ($opt->{lsassd});
    foreach my $daemonname (keys(%{$info->{lw}->{daemons}})) {
        my $daemon = $info->{lw}->{daemons}->{$daemonname};
        if ($state eq "normal" and exists($info->{logging}->{$daemon}->{proc})) {
            logInfo("Killing tap for $daemon at pid $info->{logging}->{$daemon}->{proc}->{pid}.");
            $error=killProc2(9, $info->{logging}->{$daemon}->{proc});
            if ($error) {
                logError("lwsm tap-log $daemon may still be running!");
                $gRetval |= ERR_SYSTEM_CALL;
            }
        } elsif ($state eq "normal") {
            logVerbose("Nothing to do for $daemon.");
        } else {
            logDebug("Checking if I need to tap $daemonname daemon $daemon...");
            my $daemonopt=$daemon."d";
            next unless(defined($opt->{$daemonopt}) and $opt->{$daemonopt});
            logInfo("Tapping $daemon daemon for $state mode.");
            my $tapscript = $info->{lw}->{path}."/".$info->{lwsm}->{control}." tap-log ";
            $tapscript = $tapscript.$daemon." - ";
            $tapscript = $tapscript.$state." > ";
            $tapscript = $tapscript.$info->{logpath}."/".$daemon.".log";
            logDebug("Running: $tapscript");
            my $result = System($tapscript." & ", 0, $opt->{delaytime});
            sleep 2;
            #Sleep required for background process startup on slower systems.
            $info->{logging}->{$daemon}->{proc}=findProcess("tap-log $daemon", $info);
        }
    };
}

sub changeLoggingBySyslog($$$) {
    my $info = shift || confess "no info hash passed to log starter!\n";
    my $opt = shift || confess "no options hash passed to log starter!\n";
    my $state = shift || confess "no start/stop state passed to log start!\n";
    $opt->{paclog} = "$info->{logpath}/$info->{logfile}";

    my ($error);
    if (not(defined($info->{logedit}->{file}))) {
        $info->{logedit} = {};
        $info->{logedit}->{line} = "*.*\t\t\t\t$info->{logpath}/$info->{logfile}";
        $info->{logedit}->{line} = "*.debug\t\t\t\t$info->{logpath}/$info->{logfile}" if ($info->{OStype} eq "solaris");
        $info->{logedit}->{file} = findInPath("syslog.conf", ["/etc", "/etc/syslog", "/opt/etc/", "/usr/local/etc/"]);
        if (not defined($info->{logedit}->{file}->{path})) {
            $info->{logedit}->{file} = findInPath("rsyslog.conf", ["/etc", "/etc/syslog", "/opt/etc/", "/usr/local/etc/", "/etc/rsyslog/"]);
        }
        if (not defined($info->{logedit}->{file}->{path})) {
            $info->{logedit}->{file} = findInPath("syslog-ng.conf", ["/etc", "/etc/syslog", "/opt/etc/", "/usr/local/etc/", "/etc/syslog-ng/"]);
            logError("Couldn't find syslog.conf or rsyslog.conf, and we don't support syslog-ng. Choose a different logging option!");
        }
    }
    if ($info->{logedit}->{file}->{type} eq "f") {
        if ($state eq "normal") {
            if (not defined($info->{logedit}->{line})) {
                logError("Don't know what to remove from syslog.conf!!");
                return;
            }
            logWarning("Removing debug logging from syslog.conf");
            lineDelete($info->{logedit}->{file}, $info->{logedit}->{line});
            logWarning("Changing log levels for PBIS daemons to $state");
            runTool($info, $opt, "$info->{lw}->{logging}->{netdaemon} error", "bury") if ($opt->{netlogond} and defined($info->{lw}->{logging}->{netdaemon}));
            runTool($info, $opt, "$info->{lw}->{logging}->{smbdaemon} error", "bury") if ($opt->{lwiod} and defined($info->{lw}->{logging}->{smbdaemon}));
            runTool($info, $opt, "$info->{lw}->{logging}->{authdaemon} error", "bury") if ($opt->{lsassd} and defined($info->{lw}->{logging}->{authdaemon}));
            runTool($info, $opt, "$info->{lw}->{logging}->{eventlogd} error", "bury") if ($opt->{eventlogd} and defined($info->{lw}->{logging}->{eventlogd}));
            runTool($info, $opt, "$info->{lw}->{logging}->{eventfwdd} error", "bury") if ($opt->{eventfwdd} and defined($info->{lw}->{logging}->{eventfwdd}));
            runTool($info, $opt, "$info->{lw}->{logging}->{syslogreaper} error", "bury") if ($opt->{reapsysld} and defined($info->{lw}->{logging}->{syslogreaper}));
            runTool($info, $opt, "$info->{lw}->{logging}->{regdaemon} error", "bury") if ($opt->{lwregd} and defined($info->{lw}->{logging}->{regdaemon}));
            runTool($info, $opt, "$info->{lw}->{logging}->{gpagent} error", "bury") if ($opt->{gpagentd} and defined($info->{lw}->{logging}->{gpagent}));
            #TODO Put in changes for lw 4.1
        } else {
            # Force the "messages" option on, since that's where we'll gather data from
            $opt->{messages} = 1;
            logWarning("system has syslog.conf, editing to capture debug logs");
            lineInsert($info->{logedit}->{file}, $info->{logedit}->{line});
            logWarning("Changing log levels for PBIS daemons to $state");
            runTool($info, $opt, "$info->{lw}->{logging}->{netdaemon} $state", "bury") if ($opt->{netlogond} and defined($info->{lw}->{logging}->{netdaemon}));
            runTool($info, $opt, "$info->{lw}->{logging}->{smbdaemon} $state", "bury") if ($opt->{lwiod} and defined($info->{lw}->{logging}->{smbdaemon}));
            runTool($info, $opt, "$info->{lw}->{logging}->{authdaemon} $state", "bury") if ($opt->{lsassd} and defined($info->{lw}->{logging}->{authdaemon}));
            if ($info->{OStype} eq "darwin" and $opt->{lsassd}) {
                my $odutil = findInPath("odutil", ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]);
                if ($odutil->{perm}=~/x/) {
                    runTool($info, $opt, "$odutil->{path} set log debug", "bury");
                } else {
                    killProc("DirectoryService", "USR1", $info);
                }
            }
            runTool($info, $opt, "$info->{lw}->{logging}->{eventlogd} $state", "bury") if ($opt->{eventlogd} and defined($info->{lw}->{logging}->{eventlogd}));
            runTool($info, $opt, "$info->{lw}->{logging}->{eventfwdd} $state", "bury") if ($opt->{eventfwdd} and defined($info->{lw}->{logging}->{eventfwdd}));
            runTool($info, $opt, "$info->{lw}->{logging}->{syslogreaper} $state", "bury") if ($opt->{reapsysld} and defined($info->{lw}->{logging}->{syslogreaper}));
            runTool($info, $opt, "$info->{lw}->{logging}->{regdaemon} $state", "bury") if ($opt->{lwregd} and defined($info->{lw}->{logging}->{regdaemon}));
            if ($opt->{gpagentd} and defined($info->{lw}->{logging}->{gpagent}) and $info->{lw}->{version}=~/[56]\./) {
                $state="verbose" if ($state eq "debug");
                runTool($info, $opt, "$info->{lw}->{logging}->{gpagent} $state", "bury");
            }
        }
        killProc("syslog", 1, $info);
    } else {
        $gRetval |= ERR_FILE_ACCESS;
        logError("syslog.conf is not a file, could not edit!")
    }
}
sub changeLoggingStandalone($$$) {
    my $info = shift || confess "no info hash passed to standalone log starter!\n";
    my $opt = shift || confess "no opt hash passed to standalone log starter!\n";
    my $options = shift || confess "no options hash passed to standalone log starter!\n";
    my ($startscript, $logopts, $result);
    $opt->{paclog} = "$info->{logpath}/.$info->{lw}->{daemons}->{authdaemon}.log" if ($opt->{lsassd});

    if ($opt->{lwsmd} && defined($info->{lw}->{daemons}->{lwsm})) {
        logVerbose("Attempting restart of service controller");
        $options->{daemon} = $info->{lw}->{daemons}->{lwsm};
        daemonRestart($info, $options);
        sleep 5;
    }
    if ($opt->{lwregd} && defined($info->{lw}->{daemons}->{registry})) {
        logVerbose("Attempting restart of registry daemon");
        $options->{daemon} = $info->{lw}->{daemons}->{registry};
        daemonRestart($info, $options);
        sleep 5;
    }
    if ($opt->{dcerpcd} && defined($info->{lw}->{daemons}->{dcedaemon})) {
        logVerbose("Attempting restart of dce endpoint mapper daemon");
        $options->{daemon} = $info->{lw}->{daemons}->{dcedaemon};
        daemonRestart($info, $options);
        sleep 5;
    }
    if ($opt->{netlogond} && defined($info->{lw}->{daemons}->{netdaemon})) {
        logVerbose("Attempting restart of netlogon daemon");
        $options->{daemon} = $info->{lw}->{daemons}->{netdaemon};
        daemonRestart($info, $options);
        sleep 5;
    }
    if ($opt->{lwiod} && defined($info->{lw}->{daemons}->{smbdaemon})) {
        logVerbose("Attempting restart of SMB daemon");
        $options->{daemon} = $info->{lw}->{daemons}->{smbdaemon};
        daemonRestart($info, $options);
        sleep 5;
    }
    if ($opt->{eventlogd} && defined($info->{lw}->{daemons}->{eventlogd})) {
        logVerbose("Attempting restart of eventlog daemon");
        $options->{daemon} = $info->{lw}->{daemons}->{eventlogd};
        daemonRestart($info, $options);
        sleep 5;
    }
    if ($opt->{reapsysld} && defined($info->{lw}->{daemons}->{syslogreaper})) {
        logVerbose("Attempting restart of syslog reaper");
        $options->{daemon} = $info->{lw}->{daemons}->{syslogreaper};
        daemonRestart($info, $options);
        sleep 5;
    }
    if ($opt->{lsassd} && defined($info->{lw}->{daemons}->{authdaemon})) {
        logInfo("attempting restart of auth daemon");
        $options->{daemon} = $info->{lw}->{daemons}->{authdaemon};
        if ($info->{lw}->{version} eq "4.1") {
            #TODO add code to edit lwiauthd.conf
        }
        if ($info->{OStype} eq "darwin") {
            killProc("DirectoryService", "USR1", $info);
        }
        daemonRestart($info, $options);
        sleep 5;
    }
    if ($opt->{gpagentd} && defined($info->{lw}->{daemons}->{gpdaemon})) {
        logVerbose("Attempting restart of Group Policy daemon");
        if ($info->{lw}->{version} < 5.3) {
            # not needed in LW 5.3.7724 and later
            $options->{loglevel} = 5 if ($options->{state} eq "debug");
            $options->{loglevel} = 4 if ($options->{state} eq "verbose");
            $options->{loglevel} = 3 if ($options->{state} eq "info");
            $options->{loglevel} = 2 if ($options->{state} eq "warning");
            $options->{loglevel} = 1 if ($options->{state} eq "error");
        }
        $options->{daemon} = $info->{lw}->{daemons}->{gpdaemon};
        daemonRestart($info, $options);
        sleep 5;
    }
    if ($opt->{eventfwdd} && defined($info->{lw}->{daemons}->{eventfwdd})) {
        logVerbose("Attempting restart of event forwarder daemon");
        $options->{daemon} = $info->{lw}->{daemons}->{eventfwdd};
        daemonRestart($info, $options);
        sleep 5;
    }
    if ($opt->{lwscd} && defined($info->{lw}->{daemons}->{smartcard})) {
        logVerbose("Attempting restart of smartcard daemon");
        $options->{daemon} = $info->{lw}->{daemons}->{smartcard};
        daemonRestart($info, $options);
        sleep 5;
    }
    if ($opt->{lwscd} && defined($info->{lw}->{daemons}->{pkcs11})) {
        logVerbose("Attempting restart of pkcs11 daemon");
        $options->{daemon} = $info->{lw}->{daemons}->{pkcs11};
        daemonRestart($info, $options);
        sleep 5;
    }
    if ($opt->{lwcertd} && defined($info->{lw}->{daemons}->{lwcert})) {
        logVerbose("Attempting restart of lwcert daemon");
        $options->{daemon} = $info->{lw}->{daemons}->{lwcert};
        daemonRestart($info, $options);
        sleep 5;
    }
    if ($opt->{autoenroll} && defined($info->{lw}->{daemons}->{autoenroll})) {
        logVerbose("Attempting restart of autoenroll daemon");
        $options->{daemon} = $info->{lw}->{daemons}->{autoenroll};
        daemonRestart($info, $options);
        sleep 5;
    }

}

sub changeLoggingWithContainer($$$) {
    my $info = shift;
    my $opt = shift;
    my $options = shift;
    my ($startscript, $logopts, $result);
    $opt->{paclog} = "$info->{logpath}/.$info->{lw}->{daemons}->{authdaemon}.log" if ($opt->{lsassd});

    foreach my $daemonname (keys(%{$info->{lw}->{daemons}})) {
        my $daemon = $info->{lw}->{daemons}->{$daemonname};
        logDebug("Checking if I need to restart $daemonname daemon $daemon...");
        my $daemonopt=$daemon."d";
        next unless(defined($opt->{$daemonopt}) and $opt->{$daemonopt});
        logInfo("Stopping $daemon daemon for $options->{loglevel} mode.");
        $options->{daemon} = $daemon;
        daemonContainerStop($info, $options);
    };
    foreach my $daemon(qw(netlogon lwio eventlog lsass gpagent eventfwd usermonitor reapsysl lwpcks11 lwsc lwcert autoenroll)){
        logDebug("Checking if I need to restart $daemon daemon...");
        my $daemonopt=$daemon."d";
        next unless(defined($opt->{$daemonopt}) and $opt->{$daemonopt});
        logInfo("Starting $daemon daemon for $options->{loglevel} mode.");
        $options->{daemon} = $daemon;
        daemonContainerStart($info, $options);
    };
}
sub changeLoggingWithLwSm($$$) {
    my $info=shift;
    my $opt = shift;
    my $options=shift;
    my ($startscript, $logopts, $result);
    $opt->{paclog} = "$info->{logpath}/.$info->{lw}->{daemons}->{authdaemon}.log" if ($opt->{lsassd});
    foreach my $daemonname (sort(keys(%{$info->{lw}->{daemons}}))) {
        my $daemon = $info->{lw}->{daemons}->{$daemonname};
        next unless(defined($opt->{$daemon}) and $opt->{$daemon});
        logInfo("Setting $daemonname $daemon for $options->{loglevel} mode.");
        $daemon=~s/d$//;
        if ($daemon eq "dcerpc") {
            if ($options->{loglevel} eq "normal" or $options->{loglevel} eq "error") {
                $logopts = " -f";
            } else {
                $logopts = " -D -f > ".$info->{logpath}."/".$daemon.".log";
            }
        } elsif ($daemon eq "gpagent" or $daemon eq "eventfwd") {
            if ($options->{loglevel} eq "normal" or $options->{loglevel} eq "error") {
                $logopts = ""; #TODO LW 6.0.207 doesn't support --syslog for gpagentd or eventfwd
            } else {
                $logopts = " --loglevel $options->{loglevel} --logfile ".$info->{logpath}."/".$daemon."d.log";
            }
        } else {
            if ($options->{loglevel} eq "normal" or $options->{loglevel} eq "error") {
                $logopts = " --syslog";
            } else {
                $logopts = " --loglevel $options->{loglevel} --logfile ".$info->{logpath}."/".$daemon."d.log";
            }
        }
        logVerbose("$daemon will be run with options '$logopts'");
        $startscript = $info->{lw}->{path}."/".$info->{lw}->{tools}->{regshell}.' set_value "[HKEY_THIS_MACHINE\\Services\\'.$daemon.']" "Arguments" "'.$info->{lw}->{base}.'/sbin/'.$daemon.'d'.$logopts.'"';
        logDebug("running $startscript:");
        System($startscript, 5, 5);
    }
    $options->{daemon} = $info->{lw}->{daemons}->{lwsm};
    daemonRestart($info, $options);
    sleep 5;
}

sub cleanupaftermyself {
    my $info = shift || confess "no info hash passed to cleanup!";
    my $opt = shift || confess "No opt hash passed to cleanup!";
    if ($info->{uid} != 0) {
        logError("can't restart daemons or make syslog.conf changes");
        logError("This tool needs to be run as root for these options");
        $gRetval |= ERR_SYSTEM_CALL;
        return;
    }
    tcpdumpStop($info, $opt);
    my $error;
    my $process=findProcess("lwsm tap-log", $info);
    while ((ref($process) eq "HASH") and $process->{pid}) {
        $error=killProc($process->{pid}, 9, $info);
        logError("Problem killing $process->{cmd} at pid $process->{pid}, Cleanup is unsuccessful!") if ($error);
        undef $process unless ($error);
        $process=findProcess("lwsm tap-log", $info);
    }
    if ($opt->{restart}) {
        my $stopcmd = $info->{svccontrol}->{stop1}.$info->{svccontrol}->{stop2}.$info->{svccontrol}->{stop3};
        $stopcmd=~s/daemonname/lwsmd/;
        logVerbose("Attempting to stop lwsmd via: '$stopcmd', then waiting 30 seconds for full shutdown.");
        System($stopcmd, undef, $opt->{alarmtime});
        sleep 30;
        logVerbose("Attempting to kill lwsmd, just in case");
        KillProc("lwsmd", 9, $info);
        foreach my $daemon (keys(%{$info->{lw}->{daemons}})) {
            $error=KillProc($daemon, 9, $info);
            logError("Problem killing '$daemon', Cleanup is unsuccessful!") if ($error);
            $error=KillProc("lw-container $daemon", 9, $info);
            logError("Problem killing 'lw-container $daemon', Cleanup is unsuccessful!") if ($error);
        }
        my $startcmd = $info->{svccontrol}->{start1}.$info->{svccontrol}->{start2}.$info->{svccontrol}->{start3};
        if ($info->{lw}->{lwsm}->{control} eq "lwsm") {
            $startcmd =~s/daemonname/lwsmd/;
            logInfo("Attemping to start lwsmd via '$startcmd'");
            System($startcmd, undef, $opt->{alarmtime});
            runTool($info, $opt, "lwsm autostart", "bury");
            waitForDomain($info, $opt);
        } else {
            my $options = { daemon => "",
                loglevel => "error",
            };
            changeLoggingStandAlone($info, $opt, $options);
        }
    }
}

sub determineOS($$) {
    my $info = shift || confess "no info hash passed";
    my $opt = shift || confess "no opt hash passed to determineOS!";
    logDebug("Determining OS Type...");
    my $file={};
    my $uname;

    $info->{pscmd} = "ps -ef";
    if ($^O eq "linux") {
        foreach my $i (("rpm", "dpkg")) {
            $file=findInPath($i, ["/sbin", "/usr/sbin", "/usr/bin", "/bin", "/usr/local/bin", "/usr/local/sbin"]);
            if ((defined($file->{path}))) { # && $file->{perm}=~/x/) {
                $info->{OStype} = "linux-$i";
                logVerbose("System is $info->{OStype}");
            }
        }
        $info->{timezonefile} = "/etc/sysconfig/clock";
        if (not defined($info->{OStype})) {
            $gRetval |= ERR_OS_INFO;
            logWarning("Could not determine Linux subtype");
            $info->{OStype} = "linux-unknown";
        } elsif ($info->{OStype} eq "linux-dpkg") {
            $info->{OStype} = "linux-deb"; #for consistency with other unrelated code in this project
            $info->{timezonefile} = "/etc/timezone";
        }
        logVerbose("Setting Linux paths");
        $info->{psmemfields}=[qw(user pid ppid rss vsz pcpu time comm args)];
        $info->{svcctl}->{start1} = "/etc/init.d/";
        $info->{svcctl}->{start2} = "daemonname";
        $info->{svcctl}->{start3} = " start";
        $info->{svcctl}->{stop1} = "/etc/init.d/";
        $info->{svcctl}->{stop2} = "daemonname";
        $info->{svcctl}->{stop3} = " stop";
        $info->{svcctl}->{rcpath} = "/etc/rc.d";
        $info->{tcpdump}->{startcmd} = "tcpdump";
        $info->{tcpdump}->{ifaceflag} = "-i ";
        $info->{tcpdump}->{args} = "-s0 -w";
        $info->{tcpdump}->{filter} = "not port 22";
        $info->{tcpdump}->{stopcmd} = "kill";
        $info->{sshd}->{opts} = "-ddd -p 22226";
        $info->{pampath} = "/etc/pam.d";
        $info->{nsfile} = "/etc/nsswitch.conf";
    } elsif ($^O eq "hpux") {
        $info->{OStype} = "hpux";
        logVerbose("Setting HP-UX paths");
        $info->{release} = `swlist -l bundle`;
        $info->{psmemfields}=[qw(user pid ppid sz vsz pcpu time comm args)];
        $info->{svcctl}->{start1} = "/sbin/init.d/";
        $info->{svcctl}->{start2} = "daemonname";
        $info->{svcctl}->{start3} = " start";
        $info->{svcctl}->{stop1} = "/sbin/init.d/";
        $info->{svcctl}->{stop2} = "daemonname";
        $info->{svcctl}->{stop3} = " stop";
        $info->{svcctl}->{rcpath} = "/etc/rc.d";
        $info->{tcpdump}->{startcmd} = "nettl -start; nettl";
        $info->{tcpdump}->{ifaceflag} = "-card ";
        $info->{tcpdump}->{args} = "-traceon pduin pduout -e ns_ls_driver -file";
        $info->{tcpdump}->{stopcmd} = "nettl -traceoff\; nettl -stop";
        $info->{sshd}->{opts} = "-ddd -p 22226 ";
        $info->{pampath} = "/etc/pam.conf";
        $info->{logpath} = "/var/adm";
        $info->{logfile} = "messages";
        $info->{nsfile} = "/etc/nsswitch.conf";
        $info->{timezonefile} = "/etc/TIMEZONE";
    } elsif ($^O eq "solaris") {
        $info->{OStype} = "solaris";
        logVerbose("Setting Solaris paths");
        $info->{psmemfields}=[qw(user pid ppid rss vsz pcpu time comm args)];
        $file = findInPath("svcadm", ["/usr/sbin", "/sbin"]);
        if ((defined($file->{path})) && $file->{type} eq "f") {
            $info->{svcctl}->{start1} = "$file->{path} ";
            $info->{svcctl}->{start2} = "enable -t ";
            $info->{svcctl}->{start3} = "daemonname";
            $info->{svcctl}->{stop1} = "$file->{path}";
            $info->{svcctl}->{stop2} = " disable -t ";
            $info->{svcctl}->{stop3} = "daemonname";
            $info->{pscmd} = "ps -z `/usr/bin/zonename` -f";
            $info->{zonename}=`zonename`;
            logData("Solaris 10 zonename is: ".$info->{zonename});
            if (`pkgcond is_global_zone;echo $?` == 0) {
                logData("Solaris 10 zone type is global.")
            } elsif (`pkgcond is_whole_root_nonglobal_zone;echo $?` == 0) {
                logData("Solaris 10 zone type is whole root child zone.");
            } elsif (`pkgcond is_sparse_root_nonglobal_zone;echo $?` == 0) {
                logData("Solaris 10 zone type is sparse root child zone.");
            }
        } else {
            $info->{svcctl}->{start1} = "/etc/init.d/";
            $info->{svcctl}->{start2} = "daemonname";
            $info->{svcctl}->{start3} = " start";
            $info->{svcctl}->{stop1} = "/etc/init.d/";
            $info->{svcctl}->{stop2} = "daemonname";
            $info->{svcctl}->{stop3} = " stop";
        }
        $info->{svcctl}->{rcpath} = "/etc/rc.d";
        $info->{tcpdump}->{startcmd} = "snoop";
        $info->{tcpdump}->{ifaceflag} = "-d ";
        $info->{tcpdump}->{args} = "-s0 -o";
        $info->{tcpdump}->{filter} = "not port 22";
        $info->{tcpdump}->{stopcmd} = "kill";
        $info->{sshd}->{opts} = "-ddd -p 22226 ";
        $info->{pampath} = "/etc/pam.conf";
        $info->{logpath} = "/var/adm";
        $info->{logfile} = "messages";
        $info->{nsfile} = "/etc/nsswitch.conf";
        $info->{timezonefile} = "/etc/TIMEZONE";
    } elsif ($^O eq "aix") {
        $info->{OStype} = "aix";
        logData("System release is:");
        logData(`oslevel -r`);
        logVerbose("Setting AIX paths");
        $info->{psmemfields}=[qw(user pid ppid spgsz dpgsz shmpgsz vmsize pcpu comm args)];
        $info->{svcctl}->{start1} = "/etc/rc.d/init.d/";
        $info->{svcctl}->{start2} = "daemonname";
        $info->{svcctl}->{start3} = " start";
        $info->{svcctl}->{stop1} = "/etc/rc.d/init.d/";
        $info->{svcctl}->{stop2} = "daemonname";
        $info->{svcctl}->{stop3} = " stop";
        $info->{svcctl}->{rcpath} = "/etc/rc.d";
        $info->{tcpdump}->{startcmd} = "/usr/sbin/iptrace";
        $info->{tcpdump}->{ifaceflag} = "-i";
        $info->{tcpdump}->{args} = "-a";
        $info->{tcpdump}->{stopcmd} = "kill";
        $info->{sshd}->{opts} = "-ddd -p 22226 ";
        $info->{pampath} = "/etc/pam.conf";
        $info->{logpath} = "/var/adm";
        $info->{logfile} = "syslog/syslog.log";
        $info->{nsfile} = "/etc/netsvc.conf";
        $info->{timezonefile} = "/etc/environment";
    } elsif ($^O eq "MacOS" or $^O eq "darwin") {
        $info->{OStype} = "darwin";
        logVerbose("Setting darwin paths");
        $info->{psmemfields}=[qw(user pid ppid rss vsz pcpu time comm args)];
        $info->{svcctl}->{start1} = "launchctl";
        $info->{svcctl}->{start2} = " start";
        $info->{svcctl}->{start3} = ' com.likewisesoftware.daemonname';
        $info->{svcctl}->{stop1} = "launchctl";
        $info->{svcctl}->{stop2} = " stop";
        $info->{svcctl}->{stop3} = ' com.likewisesoftware.daemonname';
        $info->{svcctl}->{rcpath} = "/etc/rc.d";
        $info->{tcpdump}->{startcmd} = "tcpdump";
        $info->{tcpdump}->{ifaceflag} = "-i ";
        $info->{tcpdump}->{args} = "-s0 -w";
        $info->{tcpdump}->{filter} = "not port 22";
        $info->{tcpdump}->{stopcmd} = "kill";
        $info->{sshd}->{opts} = "-ddd -p 22226 ";
        $info->{pampath} = "/etc/pam.d";
        $info->{logpath} = "/var/log";
        $info->{logfile} = "system.log";
        $info->{nsfile} = "/etc/nsswitch.conf";
        $info->{timezonefile} = "/etc/localtime";
    } else {
        $gRetval |= ERR_OS_INFO;
        $info->{OStype} = "unknown";
        logError("ERROR: Could not determine OS information!");
        $info->{psmemfields}=[qw(user pid ppid rss vsz pcpu time comm args)];
        $info->{timezonefile} = "/etc/localtime";
        $info->{svcctl}->{start1} = "/etc/init.d/";
        $info->{svcctl}->{start2} = "daemonname";
        $info->{svcctl}->{start3} = " start";
        $info->{svcctl}->{stop1} = "/etc/init.d/";
        $info->{svcctl}->{stop2} = "daemonname";
        $info->{svcctl}->{stop3} = " stop";
        $info->{svcctl}->{rcpath} = "/etc/rc.d";
        $info->{tcpdump}->{startcmd} = "tcpdump";
        $info->{tcpdump}->{ifaceflag} = "-i ";
        $info->{tcpdump}->{args} = "-s0 -w";
        $info->{tcpdump}->{filter} = "not port 22";
        $info->{tcpdump}->{stopcmd} = "kill";
        $info->{sshd}->{opts} = "-ddd -p 22226 ";
        $info->{pampath} = "/etc/pam.d";
        $info->{logpath} = "/var/log";
        $info->{logfile} = "messages";
        $info->{nsfile} = "/etc/nsswitch.conf";
    }
    $info->{logfiles}=[];
    foreach my $facility (("kern", "daemon", "auth")) {
        my @logs=findLogFile($facility);
        push(@logs, $info->{logpath}."/".$info->{logfile});
        if ($facility eq "daemon" and $#logs > 0) {
            $info->{logpath} = dirname($logs[0]);
            $info->{logfile} = basename($logs[0]);
            logInfo("Found $info->{logfile} via syslog config.");
        }
    }
    logData("OS: $info->{OStype}");

    $info->{platform} = $Config{myarchname};
    $info->{platform}=~s/-.*$//;
    $info->{osversion} = `uname -r`;
    $info->{uname} = `uname -a`;
    $info->{hostname} = hostname();
    logData("Version: $info->{osversion}");
    logData("Platform: $info->{platform}");
    logData("Full Uname: $info->{uname}");
    logData("System release is:");
    foreach my $i (("lsb-release", "release", "redhat-release", "ubuntu-release", "debian-release", "novell-release", "SuSE-release")) {
        $file = findInPath($i, ["/etc"]);
        if ((defined($file->{path})) && $file->{type} eq "f") {
            readFile($info, $file->{path});
            if (($i eq "redhat-release" or $i eq "centos-release") and ($opt->{syslog})) {
                my $rel;
                open($rel, "<", $i);
                while (<$rel>) {
                    if ($_=~/ 7\./) {
                        logError("Cannot issue tap-log command on RHEL7-based systems on PBIS < 8.3.4!");
                        logError("You should hit CTRL-C and re-run with the '-r' flag.");
                        logWarning("This tool has not determined the PBIS version yet.");
                        sleep 5;
                    }
                }
            }
        }
    }
    logData("LD_LIBRARY_PATH is: $ENV{LD_LIBRARY_PATH}");
    logData("LD_PRELOAD is: $ENV{LD_PRELOAD}");
    $info->{logon} = getlogin();
    $info->{name} = getpwuid($<);
    $info->{uid} = getpwnam($info->{name});
    logData("Currently running as: $info->{name} with effective UID: $info->{uid}");
    logData("Run under sudo from $info->{logon}") if ($info->{logon} ne $info->{name});
    logData("Gathered at: ".scalar(localtime));

    # set this for all OSes as false, so that future tests can have a value known to exist
    $info->{selinux} = 0;
    foreach my $i (("getrunmode", "sestatus")) {
        logVerbose("Looking for $i...");
        my $file = findInPath($i, ["/sbin", "/bin", "/usr/sbin", "/usr/bin"]);
        if (defined($file->{path})) {
            logData("---");
            logData("$i output is:");
            runTool($info, $opt, $file->{path}, "print");
            logData("---");
            if ($i eq "sestatus") {
                my $getenforce = findInPath("getenforce", ["/usr/sbin", "/sbin", "/usr/bin", "/bin"]);
                if (defined($getenforce->{path})) {
                    my @output = runTool($info, $opt, $getenforce->{path}, "return");
                    chomp $output[0];
                    logInfo("SELinux is in $output[0] mode.");
                    if ($output[0]=~/nforcing/) {
                        $info->{selinux} = 1;
                        logVerbose("Restart is disabled for SELinux in enforcing mode - tool will exit if --restart is chosen.")
                    }
                }
            }
        }
    }
    $info->{sshd} = findProcess("/sshd", $info);
    $info->{sshd_config} = findInPath("sshd_config", ["/etc/ssh", "/opt/ssh/etc", "/usr/local/etc", "/etc", "/etc/openssh", "/usr/openssh/etc", "/opt/csw/etc", "/services/ssh/etc/"]);
    $info->{krb5conf} = findInPath("krb5.conf", ["/etc/krb5", "/opt/krb5/etc", "/usr/local/etc", "/usr/local/etc/krb5", "/etc", "/opt/csw/etc"]);
    $info->{sudoers} = findInPath("sudoers", ["/etc", "/usr/local/etc", "/opt/etc", "/opt/local/etc", "/opt/usr/local/etc"]);
    $info->{sambaconf} = findInPath("smb.conf", ["/etc/samba", "/etc/smb", "/opt/etc/samba", "/usr/local/etc/samba", "/etc/opt/samba"]);
    $info->{resolvconf} = findInPath("resolv.conf", ["/etc", "/opt/etc"]);
    $info->{hostsfile} = findInPath("hosts", ["/etc/inet", "/etc"]);
    logData("Found sshd_config at $info->{sshd_config}->{path}") if ($info->{sshd_config}->{path});
    logData("Found krb5.conf at $info->{krb5conf}->{path}") if ($info->{krb5conf}->{path});
    logData("Found sudoers at $info->{sudoers}->{path}") if ($info->{sudoers}->{path});
    logData("Found smb.conf at $info->{sambaconf}->{path}") if ($info->{sambaconf}->{path});
    return $info;
}

sub waitForDomain($$) {
    my $info = shift || confess "no info hash passed to waitForDomain!\n";
    my $opt = shift || confess "no options hash passed to waitForDomain!\n";
    logInfo("Waiting up to 120 seconds for auth daemon to find domains and finish startup.");
    my ($error, $i) = (0,0);
    for ($i = 0; $i < 24; $i++) {
        sleep 5;
        $error = System("$info->{lw}->{path}/$info->{lw}->{tools}->{status} >/dev/null 2>&1", undef, $opt->{alarmtime});
        unless ($error) {
            # lw-get-status returns 0 for success, 2 if lsassd hasn't started yet
            $error=runTool($info, $opt, $info->{lw}->{tools}->{status}, "grep", "Domain:");
            # but sometimes it returns "Unknown" instead of a domain, so we'll keep looping in that case.
            last if $error;
        }
    }
}

sub gatherMemory {
    my $info = shift;
    my $opt = shift;
    my $round = 0;
    return unless ($opt->{memory});
    if (defined($info->{memory}) && ref($info->{memory}) eq "HASH") {
        $round=$info->{memory}->{round};
        logDebug("Retrieving round $round from memory.");
    } else {
        logDebug("Setting round $round in memory.");
        $info->{memory}={};
    }
    sectionBreak("Gathering Memory Stats - round $round");
    my $pshash=findInPath("ps", ["/usr/bin", "/bin", "/usr/local/bin" ] );
    my @psfields=@{$info->{psmemfields}};
    my $psopts="-e";
    my $pscmd="$pshash->{path} $psopts -o ".join(",", @psfields);
    logVerbose("using PS command: '$pscmd'");
    runTool($info, $opt, $pscmd, "print");
    foreach my $service (keys(%{$info->{lw}->{daemons}})) {
        my $daemon=$info->{lw}->{daemons}->{$service};
        logVerbose("Checking stats on service: '$service', named '$daemon'.");
        my $process=findProcess($daemon, $info);
        if (not defined($process->{pid})) {
            logVerbose("Couldn't find service $daemon in the ps list!");
            next;
        }
        my $data=runTool($info, $opt, "$pshash->{path} -p $process->{pid} -o ".join(",", @psfields), "grep", "$process->{pid}");
        logDebug("Process info is: $data");
        $data=~s/^\s+//;  # strip off leading space so the field counting works on Solaris
        my @memstats=split(/\s+/, $data);
        push(@{$info->{memory}->{$daemon}}, \@memstats);
    }
    foreach my $tool (qw(vmstat free)) {
        my $hash=findInPath($tool, ["/usr/bin", "/bin", "/usr/local/bin"]);
        if ($hash->{path}) {
            sectionBreak("Running $tool");
            runTool($info, $opt, $hash->{path}, "print");
        }
    }
    $round+=1;
    $info->{memory}->{round}=$round;
}

sub memoryStats {
    my $info = shift;
    my $opt = shift;
    my %fieldIndex;
    my $i=0;
    my @fields=@{$info->{psmemfields}};
    foreach my $field (@fields) {
        $fieldIndex{$field}=$i;
        $i++
    }
    sectionBreak("Memory utilization Statistics for PBIS");
    my $line="Daemon\t";
    foreach my $field (@fields) {
        next if ($field=~/(user|comm|arg)/);
        $line.="$field Start\t$field End\t";
    }
    logData($line);
    $line="";
    foreach my $service (keys(%{$info->{lw}->{daemons}})) {
        my $daemon=$info->{lw}->{daemons}->{$service};
        if (not defined($info->{memory}->{$daemon}) or (ref($info->{memory}->{$daemon}) ne "ARRAY")) {
            logVerbose("Not pringing information for $daemon - it wasn't running.");
            next;
        }
        $line="$daemon\t";
        foreach my $field (@fields) {
            next if ($field=~/(user|comm|arg)/);
            logDebug("Dumping stats for $daemon and $field...");
            $line.="$info->{memory}->{$daemon}->[0]->[$fieldIndex{$field}]";
            $line.="\t$info->{memory}->{$daemon}->[-1]->[$fieldIndex{$field}]\t";
        }
        logData($line);
    }
}

sub getLikewiseVersion($$) {

    # determine PBIS / Likewise version installed
    # look in reverse order, in case a bad upgrade was done
    # we can get the current running version

    my $info = shift;
    my $opt = shift;
    my $error = 0;
    my $versionFile = findInPath("ENTERPRISE_VERSION", ["/opt/pbis/data", "/opt/likewise/data", "/usr/centeris/data", "/opt/centeris/data"]);
    $versionFile = findInPath("VERSION", ["/opt/pbis/data", "/opt/likewise/data", "/usr/centeris/data", "/opt/centeris/data"]) unless(defined($versionFile->{path}) && $versionFile->{path});
    if (defined($versionFile->{path})) {
        open(VF, "<$versionFile->{path}");
        while (<VF>) {
            /VERSION=(.*)/;
            $info->{lw}->{version} = $1 if ($1 and not defined($info->{lw}->{version}));
        }
        close VF;
        my @tmparray = split(/\./, $info->{lw}->{version});
        $info->{lw}->{majorVersion} = $tmparray[0];
        logDebug("PBIS $info->{lw}->{majorVersion} is $info->{lw}->{version}.");
    } else {
        logInfo("No Version File found, determining version from binaries installed");
        my $lwsmd = findInPath("lwsmd", ["/opt/pbis/sbin"]);
        my $lwsvcd = findInPath("lwsmd", ["/opt/likewise/sbin/"]);
        my $lwregd = findInPath("lwregd", ["/opt/likewise/sbin/"]);
        my $lwiod = findInPath("lwiod", ["/opt/likewise/sbin/"]);
        my $lwrdrd = findInPath("lwrdrd", ["/opt/likewise/sbin/"]);
        my $npcmuxd = findInPath("npcmuxd", ["/opt/likewise/sbin/"]);
        my $winbindd = findInPath("winbindd", ["/opt/centeris/sbin/", "/usr/centeris/sbin"]);
        if (defined($lwsmd->{path})) {
            $info->{lw}->{version} = "7.0.0";
        } elsif  (defined($lwsvcd->{path})) {
            $info->{lw}->{version} = "6.0.0";
        } elsif (defined($lwregd->{path})) {
            $info->{lw}->{version} = "5.3.0";
        } elsif (defined($lwiod->{path})) {
            $info->{lw}->{version} = "5.2.0";
        } elsif (defined($lwrdrd->{path})) {
            $info->{lw}->{version}= "5.1.0";
        } elsif (defined($npcmuxd->{path})) {
            $info->{lw}->{version}= "5.0.0";
        } elsif (defined($winbindd->{path})) {
            $info->{lw}->{version}= "4.1";
        }
    }
    my $gporefresh = findInPath("gporefresh", ["/opt/centeris/bin/", "/usr/centeris/bin", "/opt/likewise/bin", "/opt/pbis/bin"]);
    if ($info->{lw}->{version}=~/^8\.\d+\./) {
        $info->{lw}->{base} = "/opt/pbis";
        $info->{lw}->{path} = "/opt/pbis/bin";
        $info->{lw}->{daemons}->{smbdaemon} = "lwio";
        $info->{lw}->{daemons}->{authdaemon} = "lsass";
        $info->{lw}->{daemons}->{gpdaemon} = "gpagent" if (defined($gporefresh->{path}));
        $info->{lw}->{daemons}->{dcedaemon} = "dcerpc";
        $info->{lw}->{daemons}->{netdaemon} = "netlogon";
        $info->{lw}->{daemons}->{eventlogd} = "eventlog";
        $info->{lw}->{daemons}->{eventfwdd} = "eventfwd";
        $info->{lw}->{daemons}->{syslogreaper} = "reapsysl";
        $info->{lw}->{daemons}->{registry} = "lwreg";
        $info->{lw}->{daemons}->{lwsm} = "lwsm";
        if ($info->{lw}->{version}=~/^8\.[2-5]/) {
            $info->{lw}->{daemons}->{certmgr} = "lwcert";
            $info->{lw}->{daemons}->{autoenroll} = "autoenroll";
        }
        $info->{lw}->{daemons}->{usermonitor} = "usermonitor";
        $info->{lw}->{daemons}->{smartcard} = "lwsc";
        $info->{lw}->{daemons}->{pkcs11} = "lwpkcs11";
        $info->{lw}->{logging}->{command} = "lwsm set-log-level";
        $info->{lw}->{logging}->{tapcommand} = "lwsm tap-log";
        $info->{lw}->{logging}->{registry} = "";
        $info->{lwsm}->{control}="lwsm";
        $info->{lwsm}->{type}="container";
        $info->{lwsm}->{initname}="pbis";
        $info->{lw}->{tools}->{findsid} = "find-objects --by-sid";
        $info->{lw}->{tools}->{userlist} = "enum-users --level 2";
        $info->{lw}->{tools}->{grouplist} = "enum-groups --level 1";
        $info->{lw}->{tools}->{userbyname} = "find-objects --user --by-name";
        $info->{lw}->{tools}->{userbyid} = "find-objects --user --by-unix-id";
        $info->{lw}->{tools}->{groupbyname} = "find-objects --group --by-name";
        $info->{lw}->{tools}->{groupbyid} = "find-objects --group --by-unix-id";
        $info->{lw}->{tools}->{groupsforuser} = "list-groups-for-user --show-sid";
        $info->{lw}->{tools}->{groupsforuid} = "list-groups-for-user --show-sid --uid";
        $info->{lw}->{tools}->{dctime} = "get-dc-time";
        $info->{lw}->{tools}->{config} = "config --dump";
        $info->{lw}->{tools}->{status} = "get-status";
        $info->{lw}->{tools}->{regshell} = "regshell";
        $info->{lw}->{tools}->{domainjoin} = "domainjoin-cli";
        logData("PBIS Version $info->{lw}->{version} installed");
    }  elsif ($info->{lw}->{version}=~/^7\.\d+\./) {
        $info->{lw}->{base} = "/opt/pbis";
        $info->{lw}->{path} = "/opt/pbis/bin";
        $info->{lw}->{daemons}->{smbdaemon} = "lwio";
        $info->{lw}->{daemons}->{authdaemon} = "lsass";
        $info->{lw}->{daemons}->{gpdaemon} = "gpagent" if (defined($gporefresh->{path}));
        $info->{lw}->{daemons}->{dcedaemon} = "dcerpc";
        $info->{lw}->{daemons}->{netdaemon} = "netlogon";
        $info->{lw}->{daemons}->{eventlogd} = "eventlog";
        $info->{lw}->{daemons}->{eventfwdd} = "eventfwd";
        $info->{lw}->{daemons}->{syslogreaper} = "reapsysl";
        $info->{lw}->{daemons}->{registry} = "lwreg";
        $info->{lw}->{daemons}->{lwsm} = "lwsm";
        $info->{lw}->{daemons}->{usermonitor} = "usermonitor";
        $info->{lw}->{daemons}->{smartcard} = "lwsc";
        $info->{lw}->{daemons}->{pkcs11} = "lwpkcs11";
        $info->{lw}->{logging}->{command} = "lwsm set-log-level";
        $info->{lw}->{logging}->{tapcommand} = "lwsm tap-log";
        $info->{lw}->{logging}->{registry} = "";
        $info->{lwsm}->{control}="lwsm";
        $info->{lwsm}->{type}="container";
        $info->{lwsm}->{initname}="pbis";
        $info->{lw}->{tools}->{findsid} = "find-objects --by-sid";
        $info->{lw}->{tools}->{userlist} = "enum-users --level 2";
        $info->{lw}->{tools}->{grouplist} = "enum-groups --level 1";
        $info->{lw}->{tools}->{userbyname} = "find-objects --user --by-name";
        $info->{lw}->{tools}->{userbyid} = "find-objects --user --by-unix-id";
        $info->{lw}->{tools}->{groupbyname} = "find-objects --group --by-name";
        $info->{lw}->{tools}->{groupbyid} = "find-objects --group --by-unix-id";
        $info->{lw}->{tools}->{groupsforuser} = "list-groups-for-user --show-sid";
        $info->{lw}->{tools}->{groupsforuid} = "list-groups-for-user --show-sid --uid";
        $info->{lw}->{tools}->{dctime} = "get-dc-time";
        $info->{lw}->{tools}->{config} = "config --dump";
        $info->{lw}->{tools}->{status} = "get-status";
        $info->{lw}->{tools}->{regshell} = "regshell";
        $info->{lw}->{tools}->{domainjoin} = "domainjoin-cli";
        logData("PBIS Version $info->{lw}->{version} installed");
    } elsif ($info->{lw}->{version}=~/^6\.5\./) {
        $info->{lw}->{base} = "/opt/pbis";
        $info->{lw}->{path} = "/opt/pbis/bin";
        $info->{lw}->{daemons}->{smbdaemon} = "lwio";
        $info->{lw}->{daemons}->{authdaemon} = "lsass";
        $info->{lw}->{daemons}->{gpdaemon} = "gpagent" if (defined($gporefresh->{path}));
        $info->{lw}->{daemons}->{dcedaemon} = "dcerpc";
        $info->{lw}->{daemons}->{netdaemon} = "netlogon";
        $info->{lw}->{daemons}->{eventlogd} = "eventlog";
        $info->{lw}->{daemons}->{eventfwdd} = "eventfwd";
        $info->{lw}->{daemons}->{syslogreaper} = "reapsysl";
        $info->{lw}->{daemons}->{registry} = "lwreg";
        $info->{lw}->{daemons}->{lwsm} = "lwsm";
        $info->{lw}->{daemons}->{smartcard} = "lwsc";
        $info->{lw}->{daemons}->{pkcs11} = "lwpkcs11";
        $info->{lw}->{daemons}->{startcmd} = "--start-as-daemon";
        $info->{lw}->{logging}->{command} = "lwsm set-log-level";
        $info->{lw}->{logging}->{tapcommand} = "lwsm tap-log";
        $info->{lw}->{logging}->{registry} = "";
        $info->{lwsm}->{control}="lwsm";
        $info->{lwsm}->{type}="container";
        $info->{lwsm}->{initname}="pbis";
        $info->{lw}->{tools}->{findsid} = "find-objects --by-sid";
        $info->{lw}->{tools}->{userlist} = "enum-users --level 2";
        $info->{lw}->{tools}->{grouplist} = "enum-groups --level 1";
        $info->{lw}->{tools}->{userbyname} = "find-objects --user --by-name";
        $info->{lw}->{tools}->{userbyid} = "find-objects --user --by-unix-id";
        $info->{lw}->{tools}->{groupbyname} = "find-objects --group --by-name";
        $info->{lw}->{tools}->{groupbyid} = "find-objects --group --by-unix-id";
        $info->{lw}->{tools}->{groupsforuser} = "list-groups-for-user --show-sid";
        $info->{lw}->{tools}->{groupsforuid} = "list-groups-for-user --show-sid --uid";
        $info->{lw}->{tools}->{dctime} = "get-dc-time";
        $info->{lw}->{tools}->{config} = "config --dump";
        $info->{lw}->{tools}->{status} = "get-status";
        $info->{lw}->{tools}->{regshell} = "regshell";
        $info->{lw}->{tools}->{domainjoin} = "domainjoin-cli";
        logData("PBIS Version 6.5 installed");
    } elsif ($info->{lw}->{version} == "6.0.0") {
        $info->{lw}->{base} = "/opt/likewise";
        $info->{lw}->{path} = "/opt/likewise/bin";
        $info->{lw}->{daemons}->{smbdaemon} = "lwiod";
        $info->{lw}->{daemons}->{authdaemon} = "lsassd";
        $info->{lw}->{daemons}->{gpdaemon} = "gpagentd" if (defined($gporefresh->{path}));
        $info->{lw}->{daemons}->{dcedaemon} = "dcerpcd";
        $info->{lw}->{daemons}->{netdaemon} = "netlogond";
        $info->{lw}->{daemons}->{eventlogd} = "eventlogd";
        $info->{lw}->{daemons}->{eventfwdd} = "eventfwdd";
        $info->{lw}->{daemons}->{syslogreaper} = "reapsysld";
        $info->{lw}->{daemons}->{registry} = "lwregd";
        $info->{lw}->{daemons}->{lwsm} = "lwsmd";
        $info->{lw}->{daemons}->{startcmd} = "--start-as-daemon";
        $info->{lw}->{logging}->{smbdaemon} = "lwio-set-log-level";
        $info->{lw}->{logging}->{authdaemon} = "lw-set-log-level";
        $info->{lw}->{logging}->{netdaemon} = "lwnet-set-log-level";
        $info->{lw}->{logging}->{eventfwdd} = "evtfwd-set-log-level";
        $info->{lw}->{logging}->{syslogreaper} = "rsys-set-log-level";
        $info->{lw}->{logging}->{gpagent} = "gp-set-log-level";
        $info->{lw}->{logging}->{registry} = "";
        $info->{lwsm}->{control}="lwsm";
        $info->{lwsm}->{type}="standalone";
        $info->{lwsm}->{initname}="likewise-open";
        $info->{lw}->{tools}->{findsid} = "lw-find-by-sid";
        $info->{lw}->{tools}->{userlist} = "lw-enum-users --level 2";
        $info->{lw}->{tools}->{grouplist} = "lw-enum-groups --level 1";
        $info->{lw}->{tools}->{userbyname} = "lw-find-user-by-name --level 2";
        $info->{lw}->{tools}->{userbyid} = "lw-find-user-by-id --level 2";
        $info->{lw}->{tools}->{groupbyname} = "lw-find-group-by-name --level 1";
        $info->{lw}->{tools}->{groupbyid} = "lw-find-group-by-id --level 1";
        $info->{lw}->{tools}->{groupsforuser} = "lw-list-groups-for-user --show-sid";
        $info->{lw}->{tools}->{groupsforuid} = "lw-list-groups-for-user --show-sid --uid";
        $info->{lw}->{tools}->{dctime} = "lw-get-dc-time";
        $info->{lw}->{tools}->{status} = "lw-get-status";
        $info->{lw}->{tools}->{config} = "lwconfig --dump";
        $info->{lw}->{tools}->{regshell} = "lwregshell";
        $info->{lw}->{tools}->{domainjoin} = "domainjoin-cli";
        logData("Likewise Version 6.0 installed");
    } elsif ($info->{lw}->{version} == "5.4.0") {
        $info->{lw}->{base} = "/opt/likewise";
        $info->{lw}->{path} = "/opt/likewise/bin";
        $info->{lw}->{daemons}->{smbdaemon} = "lwiod";
        $info->{lw}->{daemons}->{authdaemon} = "lsassd";
        $info->{lw}->{daemons}->{gpdaemon} = "gpagentd" if (defined($gporefresh->{path}));
        $info->{lw}->{daemons}->{dcedaemon} = "dcerpcd";
        $info->{lw}->{daemons}->{netdaemon} = "netlogond";
        $info->{lw}->{daemons}->{eventlogd} = "eventlogd";
        $info->{lw}->{daemons}->{eventfwdd} = "eventfwdd";
        $info->{lw}->{daemons}->{syslogreaper} = "reapsysld";
        $info->{lw}->{daemons}->{registry} = "lwregd";
        $info->{lw}->{daemons}->{lwsm} = "lwsmd";
        $info->{lw}->{daemons}->{startcmd} = "--start-as-daemon";
        $info->{lw}->{logging}->{smbdaemon} = "lwio-set-log-level";
        $info->{lw}->{logging}->{authdaemon} = "lw-set-log-level";
        $info->{lw}->{logging}->{netdaemon} = "lwnet-set-log-level";
        $info->{lw}->{logging}->{eventfwdd} = "evtfwd-set-log-level";
        $info->{lw}->{logging}->{syslogreaper} = "rsys-set-log-level";
        $info->{lw}->{logging}->{registry} = "reg-set-log-level";
        $info->{lwsm}->{control}="lwsm";
        $info->{lwsm}->{type}="standalone";
        $info->{lwsm}->{initname}="likewise-open";
        $info->{lw}->{tools}->{findsid} = "lw-find-by-sid";
        $info->{lw}->{tools}->{userlist} = "lw-enum-users --level 2";
        $info->{lw}->{tools}->{grouplist} = "lw-enum-groups --level 1";
        $info->{lw}->{tools}->{userbyname} = "lw-find-user-by-name --level 2";
        $info->{lw}->{tools}->{userbyid} = "lw-find-user-by-id --level 2";
        $info->{lw}->{tools}->{groupbyname} = "lw-find-group-by-name --level 1";
        $info->{lw}->{tools}->{groupbyid} = "lw-find-group-by-id --level 1";
        $info->{lw}->{tools}->{groupsforuser} = "lw-list-groups-for-user --show-sid";
        $info->{lw}->{tools}->{groupsforuid} = "lw-list-groups-for-user --show-sid --uid";
        $info->{lw}->{tools}->{dctime} = "lw-get-dc-time";
        $info->{lw}->{tools}->{config} = "lwconfig --dump";
        $info->{lw}->{tools}->{status} = "lw-get-status";
        $info->{lw}->{tools}->{domainjoin} = "domainjoin-cli";
        logData("Likewise Version 5.4 installed");
    } elsif ($info->{lw}->{version} == "5.3.0") {
        $info->{lw}->{base} = "/opt/likewise";
        $info->{lw}->{path} = "/opt/likewise/bin";
        $info->{lw}->{daemons}->{lwsm} = "lwsmd";
        $info->{lw}->{daemons}->{smbdaemon} = "lwiod";
        $info->{lw}->{restart}->{smbdaemon} = "lwsm restart lwio";
        $info->{lw}->{daemons}->{authdaemon} = "lsassd";
        $info->{lw}->{restart}->{authdaemon} = "lwsm restart lsass";
        $info->{lw}->{daemons}->{gpdaemon} = "gpagentd" if (defined($gporefresh->{path}));
        $info->{lw}->{restart}->{gpdaemon} = "lwsm restart gpagentd" if (defined($gporefresh->{path}));
        $info->{lw}->{daemons}->{dcedaemon} = "dcerpcd";
        $info->{lw}->{restart}->{dcedaemon} = "lwsm restart dcerpc";
        $info->{lw}->{daemons}->{netdaemon} = "netlogond";
        $info->{lw}->{restart}->{netdaemon} = "lwsm restart netlogon";
        $info->{lw}->{daemons}->{eventlogd} = "eventlogd";
        $info->{lw}->{restart}->{eventlogd} = "lwsm restart eventlog";
        $info->{lw}->{daemons}->{eventfwdd} = "eventfwdd";
        $info->{lw}->{restart}->{eventfwdd} = "lwsm restart eventfwd";
        $info->{lw}->{daemons}->{syslogreaper} = "reapsysld";
        $info->{lw}->{restart}->{syslogreaper} = "lwsm restart reapsysl";
        $info->{lw}->{daemons}->{registry} = "lwregd";
        $info->{lw}->{restart}->{registry} = "lwsm restart lwreg";
        $info->{lw}->{daemons}->{smartcard} = "lwscd";
        $info->{lw}->{restart}->{smartcard} = "lwsm restart lwscd";
        $info->{lw}->{daemons}->{pkcs11} = "lwpkcs11d";
        $info->{lw}->{restart}->{pkcs11} = "lwsm restart lwpkcs11";
        $info->{lw}->{daemons}->{startcmd} = "--start-as-daemon";
        $info->{lw}->{logging}->{smbdaemon} = "lwio-set-log-level";
        $info->{lw}->{logging}->{authdaemon} = "lw-set-log-level";
        $info->{lw}->{logging}->{netdaemon} = "lwnet-set-log-level";
        $info->{lw}->{logging}->{eventfwdd} = "evtfwd-set-log-level";
        $info->{lw}->{logging}->{syslogreaper} = "rsys-set-log-level";
        $info->{lwsm}->{control}="init";
        $info->{lwsm}->{type}="standalone";
        $info->{lw}->{tools}->{findsid} = "lw-find-by-sid";
        $info->{lw}->{tools}->{userlist} = "lw-enum-users --level 2";
        $info->{lw}->{tools}->{grouplist} = "lw-enum-groups --level 1";
        $info->{lw}->{tools}->{userbyname} = "lw-find-user-by-name --level 2";
        $info->{lw}->{tools}->{userbyid} = "lw-find-user-by-id --level 2";
        $info->{lw}->{tools}->{groupbyname} = "lw-find-group-by-name --level 1";
        $info->{lw}->{tools}->{groupbyid} = "lw-find-group-by-id --level 1";
        $info->{lw}->{tools}->{groupsforuser} = "lw-list-groups-for-user --show-sid";
        $info->{lw}->{tools}->{groupsforuid} = "lw-list-groups-for-user --show-sid --uid";
        $info->{lw}->{tools}->{dctime} = "lw-get-dc-time";
        $info->{lw}->{tools}->{config} = "cat /etc/likewise/lsassd.conf";
        $info->{lw}->{tools}->{status} = "lw-get-status";
        $info->{lw}->{tools}->{domainjoin} = "domainjoin-cli";
        logData("Likewise Version 5.3 installed");
    } elsif ($info->{lw}->{version} == "5.2.0") {
        $info->{lw}->{base} = "/opt/likewise";
        $info->{lw}->{path} = "/opt/likewise/bin";
        $info->{lw}->{daemons}->{smbdaemon} = "lwiod";
        $info->{lw}->{daemons}->{authdaemon} = "lsassd";
        $info->{lw}->{daemons}->{gpdaemon} = "gpagentd" if (defined($gporefresh->{path}));
        $info->{lw}->{daemons}->{dcedaemon} = "dcerpcd";
        $info->{lw}->{daemons}->{netdaemon} = "netlogond";
        $info->{lw}->{daemons}->{eventlogd} = "eventlogd";
        $info->{lw}->{daemons}->{startcmd} = "--start-as-daemon";
        $info->{lw}->{logging}->{smbdaemon} = "lwio-set-log-level";
        $info->{lw}->{logging}->{authdaemon} = "lw-set-log-level";
        $info->{lw}->{logging}->{eventfwdd} = "evtfwd-set-log-level";
        $info->{lwsm}->{control}="init";
        $info->{lwsm}->{type}="standalone";
        $info->{lw}->{tools}->{findsid} = "lw-find-by-sid";
        $info->{lw}->{tools}->{userlist} = "lw-enum-users --level 2";
        $info->{lw}->{tools}->{grouplist} = "lw-enum-groups --level 1";
        $info->{lw}->{tools}->{userbyname} = "lw-find-user-by-name --level 2";
        $info->{lw}->{tools}->{userbyid} = "lw-find-user-by-id --level 2";
        $info->{lw}->{tools}->{groupbyname} = "lw-find-group-by-name --level 1";
        $info->{lw}->{tools}->{groupbyid} = "lw-find-group-by-id --level 1";
        $info->{lw}->{tools}->{groupsforuser} = "lw-list-groups";
        $info->{lw}->{tools}->{dctime} = "lw-get-dc-time";
        $info->{lw}->{tools}->{config} = "cat /etc/likewise/lsassd.conf";
        $info->{lw}->{tools}->{status} = "lw-get-status";
        $info->{lw}->{tools}->{domainjoin} = "domainjoin-cli";
        logData("Likewise Version 5.2 installed");
    } elsif ($info->{lw}->{version} == "5.1.0") {
        $info->{lw}->{base} = "/opt/likewise";
        $info->{lw}->{path} = "/opt/likewise/bin";
        $info->{lw}->{daemons}->{smbdaemon} = "lwrdrd";
        $info->{lw}->{daemons}->{authdaemon} = "lsassd";
        $info->{lw}->{daemons}->{gpdaemon} = "gpagentd" if (defined($gporefresh->{path}));
        $info->{lw}->{daemons}->{dcedaemon} = "dcerpcd";
        $info->{lw}->{daemons}->{netdaemon} = "netlogond";
        $info->{lw}->{daemons}->{eventlogd} = "eventlogd";
        $info->{lw}->{daemons}->{startcmd} = "2>&1 &";
        $info->{lw}->{logging}->{smbdaemon} = "lw-smb-set-log-level";
        $info->{lw}->{logging}->{authdaemon} = "lw-set-log-level";
        $info->{lwsm}->{control}="init";
        $info->{lwsm}->{type}="standalone";
        $info->{lw}->{tools}->{userlist} = "lw-enum-users --level 2";
        $info->{lw}->{tools}->{grouplist} = "lw-enum-groups --level 1";
        $info->{lw}->{tools}->{userbyname} = "lw-find-user-by-name --level 2";
        $info->{lw}->{tools}->{userbyid} = "lw-find-user-by-id --level 2";
        $info->{lw}->{tools}->{groupbyname} = "lw-find-group-by-name --level 1";
        $info->{lw}->{tools}->{groupbyid} = "lw-find-group-by-id --level 1";
        $info->{lw}->{tools}->{groupsforuser} = "lw-list-groups";
        $info->{lw}->{tools}->{dctime} = "lw-get-dc-time";
        $info->{lw}->{tools}->{config} = "cat /etc/likewise/lsassd.conf";
        $info->{lw}->{tools}->{status} = "lw-get-status";
        $info->{lw}->{tools}->{domainjoin} = "domainjoin-cli";
        logData("Likewise Version 5.1 installed");
    } elsif ($info->{lw}->{version} == "5.0.0") {
        $info->{lw}->{base} = "/opt/likewise";
        $info->{lw}->{path} = "/opt/likewise/bin";
        $info->{lw}->{daemons}->{smbdaemon} = "npcmuxd";
        $info->{lw}->{daemons}->{authdaemon} = "lsassd";
        $info->{lw}->{daemons}->{gpdaemon} = "gpagentd" if (defined($gporefresh->{path}));
        $info->{lw}->{daemons}->{dcedaemon} = "dcerpcd";
        $info->{lw}->{daemons}->{netdaemon} = "netlogond";
        $info->{lw}->{daemons}->{eventlogd} = "eventlogd";
        $info->{lw}->{daemons}->{startcmd} = "2>&1 &";
        $info->{lw}->{logging}->{authdaemon} = "lw-set-log-level";
        $info->{lwsm}->{control}="init";
        $info->{lwsm}->{type}="standalone";
        $info->{lw}->{tools}->{userlist} = "lw-enum-users --level 2";
        $info->{lw}->{tools}->{grouplist} = "lw-enum-groups --level 1";
        $info->{lw}->{tools}->{userbyname} = "lw-find-user-by-name --level 2";
        $info->{lw}->{tools}->{userbyid} = "lw-find-user-by-id --level 2";
        $info->{lw}->{tools}->{groupbyname} = "lw-find-group-by-name --level 1";
        $info->{lw}->{tools}->{groupbyid} = "lw-find-group-by-id --level 1";
        $info->{lw}->{tools}->{groupsforuser} = "lw-list-groups";
        $info->{lw}->{tools}->{dctime} = "lw-get-dc-time";
        $info->{lw}->{tools}->{config} = "cat /etc/likewise/lsassd.conf";
        $info->{lw}->{tools}->{status} = "lw-get-status";
        $info->{lw}->{tools}->{domainjoin} = "domainjoin-cli";
        logData("Likewise Version 5.0 installed");
    } elsif ($info->{lw}->{version} == "4.1") {
        if ($info->{OStype}=~/linux/) {
            $info->{lw}->{base} = "/usr/centeris";
            $info->{lw}->{path} = "/usr/centeris/bin";
        } else {
            $info->{lw}->{base} = "/opt/centeris";
            $info->{lw}->{path} = "/opt/centeris/bin";
        }
        $info->{lw}->{daemons}->{smbdaemon} = "centeris.com-npcmuxd";
        $info->{lw}->{daemons}->{authdaemon} = "winbindd";
        $info->{lw}->{daemons}->{gpdaemon} = "centeris.com-gpagentd" if (defined($gporefresh->{path}));
        $info->{lw}->{daemons}->{dcedaemon} = "centeris.com-dcerpcd";
        $info->{lw}->{daemons}->{startcmd} = "2>&1 &";
        $info->{lwsm}->{control}="init";
        $info->{lwsm}->{type}="standalone";
        $info->{lw}->{tools}->{userlist} = "lwiinfo -U";
        $info->{lw}->{tools}->{grouplist} = "lwiinfo -G";
        $info->{lw}->{tools}->{userbyname} = "lwiinfo -i";
        $info->{lw}->{tools}->{userbyid} = "lwiinfo --uid-info";
        $info->{lw}->{tools}->{groupbyname} = "lwiinfo -g";
        $info->{lw}->{tools}->{groupbyid} = "lwiinfo --gid-info";
        $info->{lw}->{tools}->{status} = "lwiinfo -pmt";
        $info->{lw}->{tools}->{config} = "cat /etc/centeris/lwiauthd.conf";
        $info->{lw}->{tools}->{domainjoin} = "domainjoin-cli";
        logData("Likewise Version 4.1 installed");
    }
    readFile($info, $versionFile->{path});
    if ($versionFile->{path}=~/ENTERPRISE/) {
        logDebug("PBIS Enterprise installed, printing Platform information");
        my $platformFile=$versionFile->{path};
        $platformFile=~s/ENTERPRISE_//g;
        readFile($info, $platformFile);
        $info->{emailaddress} = 'pbis-support@beyondtrust.com';
    }

    if (not defined($gporefresh->{path})) {
        # PBIS / Likewise Open doesn't include gporefresh or the following daemons, so mark them undef,
        # This way, we won't attempt to restart them later, or do anything with them.
        # Reduces errors printed to screen.
        undef $info->{lw}->{daemons}->{gpdaemon};
        undef $info->{lw}->{daemons}->{eventfwd};
        undef $info->{lw}->{daemons}->{syslogreaper};
        undef $info->{lw}->{daemons}->{usermonitor};
        $info->{emailaddress} = 'openproject@beyondtrust.com';
        #disable group policy tests, too.
        $opt->{gpagentd}=0;
        $opt->{gpo}=0;
    }
}

sub outputReport($$) {
    my $info=shift || confess "no info hash passed to reporting!\n";
    my $opt=shift || confess "no options hash passed to reporting!\n";

    sectionBreak("Gathering Logfiles");
    my ($tarballfile, $error, $appendfile);
    if (-d $opt->{tarballdir} && (-w $opt->{tarballdir})) {
        $tarballfile = $opt->{tarballdir}."/".$opt->{tarballfile};
    } elsif (-w "./") {
        $tarballfile = "./".$opt->{tarballfile};
    } else {
        $gRetval |= ERR_FILE_ACCESS;
        logError("Can't write log tarball $opt->{tarballfile}$opt->{tarballext}!");
        logError("both $opt->{tarballdir} and ./ are non-writable!");
        return $gRetval;
    }
    if (-e $tarballfile.$opt->{tarballext}) {
        logWarning("WARNING: file $tarballfile".$opt->{tarballext}." exists, adding ext...");
        for ($error=0; $error<99; $error++) {
            my $num = sprintf("%02d", $error);
            unless (-e $tarballfile."-$num".$opt->{tarballext}) {
                $tarballfile = $tarballfile."-$num".$opt->{tarballext};
                last;
            }
        }
    } else {
        $tarballfile = $tarballfile.$opt->{tarballext};
    }
    if ($tarballfile=~/\.gz$/) {
        #now that we know that the gz file is safe to create,
        #strip the .gz extension, so it can be gzipped later
        logDebug("Creating tarball as tar only, will gzip at end.");
        $tarballfile=~s/\.gz$//;
    }
    logVerbose("Creating tarball $tarballfile and adding logs");
    if ($opt->{restart} or $info->{lwsm}->{type} eq "container") {
        if ($opt->{lsassd}) {
            logInfo("Adding auth daemon log");
            $appendfile = $info->{logpath}."/".$info->{lw}->{daemons}->{authdaemon}.".log";
            tarFiles($info, $opt, $tarballfile, $appendfile);
        }
        if ($opt->{lwiod}) {
            logInfo("Adding SMB Daemon log");
            $appendfile = $info->{logpath}."/".$info->{lw}->{daemons}->{smbdaemon}.".log";
            tarFiles($info, $opt, $tarballfile, $appendfile);
        }
        if ($opt->{netlogond}) {
            logInfo("adding netlogond log");
            $appendfile = $info->{logpath}."/".$info->{lw}->{daemons}->{netdaemon}.".log";
            tarFiles($info, $opt, $tarballfile, $appendfile);
        }
        if ($opt->{gpagentd} and defined($info->{lw}->{daemons}->{gpdaemon})) {
            logInfo("Adding gpagentd log");
            $appendfile = $info->{logpath}."/".$info->{lw}->{daemons}->{gpdaemon}.".log";
            tarFiles($info, $opt, $tarballfile, $appendfile);
        }
        if ($opt->{eventlogd}) {
            logInfo("Adding eventlogd log");
            $appendfile = $info->{logpath}."/".$info->{lw}->{daemons}->{eventlogd}.".log";
            tarFiles($info, $opt, $tarballfile, $appendfile);
        }
        if ($opt->{eventfwdd} and defined($info->{lw}->{daemons}->{eventfwd})) {
            logInfo("Adding eventfwdd log");
            $appendfile = $info->{logpath}."/".$info->{lw}->{daemons}->{eventfwdd}.".log";
            tarFiles($info, $opt, $tarballfile, $appendfile);
        }
        if ($opt->{lwregd}) {
            logInfo("Adding registry log");
            $appendfile = $info->{logpath}."/".$info->{lw}->{daemons}->{registry}.".log";
            tarFiles($info, $opt, $tarballfile, $appendfile);
        }
        if ($opt->{lwsmd}) {
            logInfo("Adding service controller log");
            $appendfile = $info->{logpath}."/".$info->{lw}->{daemons}->{lwsm}.".log";
            tarFiles($info, $opt, $tarballfile, $appendfile);
        }
        if ($opt->{reapsysld} and defined($info->{lw}->{daemons}->{syslogreaper})) {
            logInfo("Adding syslog reaper log");
            $appendfile = $info->{logpath}."/".$info->{lw}->{daemons}->{syslogreaper}.".log";
            tarFiles($info, $opt, $tarballfile, $appendfile);
        }
        if ($opt->{usermonitor} and defined($info->{lw}->{daemons}->{usermonitor})) {
            logInfo("Adding usermonitor log");
            $appendfile = $info->{logpath}."/".$info->{lw}->{daemons}->{usermonitor}.".log";
            tarFiles($info, $opt, $tarballfile, $appendfile);
        }
        if ($opt->{certmgr} and defined($info->{lw}->{daemons}->{certmgr})) {
            logInfo("Adding lwcert logs.");
            $appendfile = $info->{logpath}."/".$info->{lw}->{daemons}->{certmgr}.".log";
            tarFiles($info, $opt, $tarballfile, $appendfile);
            $appendfile = $info->{logpath}."/".$info->{lw}->{daemons}->{autoenroll}.".log";
            tarFiles($info, $opt, $tarballfile, $appendfile);
        }
    }
    tarFiles($info, $opt, $tarballfile, "/Library/Logs/DirectoryService/DirectoryService.debug.log") if ($info->{OStype} eq "darwin");
    if ($info->{OStype} eq "aix") {
        tarFiles($info, $opt, $tarballfile, "/etc/security/aixpert");
        tarFiles($info, $opt, $tarballfile, "/etc/security/user");
        tarFiles($info, $opt, $tarballfile, "/etc/security/group");
        tarFiles($info, $opt, $tarballfile, "/usr/lib/security/methods.cfg") if (-f "/usr/lib/security/methods.cfg");
        tarFiles($info, $opt, $tarballfile, "/etc/security/methods.cfg") if (-f "/etc/security/methods.cfg");
        tarFiles($info, $opt, $tarballfile, "/etc/security/login.cfg") if (-f "/etc/security/login.cfg");
    }
    if ($opt->{messages}) {
        foreach my $file (@{$info->{logfiles}}) {
            logInfo("Adding syslog logfile $file...");
            tarFiles($info, $opt, $tarballfile, $file);
        }
    }
    if ($opt->{domainjoin}) {
        tarFiles($info, $opt, $tarballfile, $opt->{djlog});
    }
    if ($opt->{automounts}) {
        logInfo("Adding autofs files from PBIS GPO");
        tarFiles($info, $opt, $tarballfile, "/etc/lwi_automount");
        tarFiles($info, $opt, $tarballfile, "/etc/auto*");
    }
    if ($opt->{sambalogs} and $info->{sambaconf}) {
        tarFiles($info, $opt, $tarballfile, "$info->{logpath}/samba");
        if ($info->{logpath} ne "/var/log") {
            logDebug("Adding files from /var/log/samba also");
            tarFiles($info, $opt, $tarballfile, "/var/log/samba");
        }
        tarFiles($info, $opt, $tarballfile, "$info->{sambaconf}->{dir}");
    } else {
        tarFiles($info, $opt, $tarballfile, "$info->{sambaconf}->{path}") if ($info->{sambaconf}->{path});
    }
    logInfo("Adding sshd_config");
    tarFiles($info, $opt, $tarballfile, $info->{sshd_config}->{path}) if ($info->{sshd_config}->{path});
    logError("Can't find sshd_config to add to tarball!") unless ($info->{sshd_config}->{path});
    tarFiles($info, $opt, $tarballfile, $info->{logpath}."/sshd-pbis.log");
    # 20141031 - RCA - Solaris 11 now uses pam.d as well as pam.conf
    # so we'll grab everything. Keeping the old $info->{pampath} allows for REAL weidness if we find it later
    tarFiles($info, $opt, $tarballfile, $info->{pampath});
    tarFiles($info, $opt, $tarballfile, "/etc/pam.conf");
    tarFiles($info, $opt, $tarballfile, "/etc/pam.d");
    tarFiles($info, $opt, $tarballfile, "/etc/nscd.conf");
    if ( -d "/etc/pb") {
        tarFiles($info, $opt, $tarballfile, "/etc/pb");
        tarFiles($info, $opt, $tarballfile, "/etc/pb.settings");
        tarFiles($info, $opt, $tarballfile, "/etc/pb.conf");
    }
    tarFiles($info, $opt, $tarballfile, $info->{krb5conf}->{path}) if ($info->{krb5conf}->{path});
    tarFiles($info, $opt, $tarballfile, $info->{logedit}->{path}) if ($info->{logedit}->{path});
    logError("Can't find krb5.conf to add to tarball!") unless ($info->{krb5conf}->{path});
    if ($opt->{sudo}) {
        tarFiles($info, $opt, $tarballfile, $info->{sudoers}->{path}) if ($info->{sudoers}->{path});
        logError("Can't find sudoers to add to tarball!") unless ($info->{sudoers}->{path});
    }
    if ($opt->{tcpdump}) {
        tarFiles($info, $opt, $tarballfile, $opt->{capturefile});
        # grab the keytab, so we can decrypt the LDAP traffic.
        tarFiles($info, $opt, $tarballfile, "/etc/krb5.keytab");
    }
    if (defined($opt->{gatherdb}) and $opt->{gatherdb} = 1) {
        logInfo("Adding Likewise DB folder (this may take a while if the eventlog is large)...");
        tarFiles($info, $opt, $tarballfile, "/var/lib/likewise/db");
        tarFiles($info, $opt, $tarballfile, "/var/lib/pbis/db");
    }
    if (defined($opt->{gpo}) and $opt->{gpo} = 1) {
        logInfo("Adding PBIS Group Policy cache...");
        tarFiles($info, $opt, $tarballfile, "/var/lib/likewise/grouppolicy");
        tarFiles($info, $opt, $tarballfile, "/var/lib/pbis/grouppolicy");
    }

    # Files to add under all circumstances
    logInfo("Adding PBIS Configuration...");
    tarFiles($info, $opt, $tarballfile, "/etc/likewise");
    tarFiles($info, $opt, $tarballfile, "/etc/pbis");
    tarFiles($info, $opt, $tarballfile, "/etc/nscd.conf");
    tarFiles($info, $opt, $tarballfile, $info->{nsfile});
    tarFiles($info, $opt, $tarballfile, $info->{timezonefile});
    if (defined($info->{hostsfile}->{path})) {
        tarFiles($info, $opt, $tarballfile, $info->{hostsfile}->{path});
    }
    if (defined($info->{resolvconf}->{path})) {
        tarFiles($info, $opt, $tarballfile, $info->{resolvconf}->{path});
    }
    if (-e "$info->{logpath}/pbis-enterprise-install.log") {
        tarFiles($info, $opt, $tarballfile, "$info->{logpath}/pbis-enterprise-install.log");
    }
    if (-e "$info->{logpath}/pbis-open-install.log") {
        tarFiles($info, $opt, $tarballfile, "$info->{logpath}/pbis-enterprise-install.log");
    }
    if (-e "$info->{logpath}/$info->{hostname}-likewise-install-results.out") {
        logInfo("Adding ProServe install logfile $info->{hostname}-likewise-install-results.out");
        logWarning("Customer should not be using these tools for non-migration purposes.");
        tarFiles($info, $opt, $tarballfile, "$info->{logpath}/$info->{hostname}-likewise-install-results.out");
    }
    if (-e "/var/log/pbislogs") {
        logInfo("Adding ProServe install logfile directory /var/log/pbislogs");
        logWarning("Customer should not be using these tools for non-migration purposes.");
        tarFiles($info, $opt, $tarballfile, "/var/log/pbislogs");
        if (-e "/root/.pbis-backup") {
            logInfo("Adding ProServe install backup director /root/.pbis-backup");
            tarFiles($info, $opt, $tarballfile, "/root/.pbis-backup");
        }
    }
    if (-e "$info->{logpath}/$info->{hostname}-pbis-install-results.out") {
        logInfo("Adding ProServe install logfile $info->{hostname}-pbis-install-results.out");
        logWarning("Customer should not be using these tools for non-migration purposes.");
        tarFiles($info, $opt, $tarballfile, "$info->{logpath}/$info->{hostname}-pbis-install-results.out");
    }
    logInfo("Finished adding files, now for our output");
    if ($opt->{logfile} eq "-") {
        logError("Can't add STDOUT to tarball - you need to run with an actual logfile!");
    } else {
        tarFiles($info, $opt, $tarballfile, $opt->{logfile});
    }
    if ($opt->{tarballext}=~/\.gz$/) {
        logInfo("Output gathered, now gzipping for email");
        $error = System("gzip $tarballfile", undef, $opt->{alarmtime});
        if ($error) {
            $gRetval |= ERR_SYSTEM_CALL;
            logError("Can't gzip $tarballfile - $!");
        } else {
            $tarballfile = "$tarballfile.gz";
        }
    }
    logData("All data gathered successfully in $tarballfile.");
    logData("Please email $tarballfile to $info->{emailaddress} to help diagnose your problem");
}

sub runTests($$) {
    my $info = shift || confess "no info hash passed to test runner!\n";
    my $opt = shift || confess "no options hash passed to test runner!\n";
    my $data;

    gatherMemory($info, $opt);
    # It makes no sense to run most of the below tests if you're not joined, so... let's do that test first
    if ($opt->{domainjoin}) {
        sectionBreak("domainjoin");
        my ($djoptions, $djcommand, $domain, $user, $djlog)=("","","","","");
        if ($opt->{djcommand}) {
            $djcommand = $opt->{djcommand};
            logDebug("Domainjoin command is $djcommand");
        }
        if ($opt->{djlog}) {
            $djlog = "--loglevel verbose --logfile $opt->{djlog}";
            logDebug("Domainjoin log is $djlog");
        }
        while (not $djcommand) {
            logData("Please enter the domainjoin command below.");
            logData("Likely commands may be: 'join', 'configure', 'query', or 'leave'.");
            $djcommand = <STDIN>;
            chomp $djcommand;
            if ($djcommand=~/^\bhelp\b$/i) {
                runTool($info, $opt, "$info->{lw}->{tools}->{domainjoin} --$djcommand", "print");
                $djcommand = "";
            }
            $opt->{djcommand} = $djcommand;
            if ($djcommand!~/^(join|query|configure|leave|fixfqdn|setname)$/i) {
                $djcommand = "";
                LogData("Invalid domainjoin command, please try again.");
            }
        }
        if ($djcommand!~/(leave|query)/) {
            if ($opt->{djoptions}) {
                $djoptions = $opt->{djoptions};
            }
            while (not $djoptions) {
                logData("Please enter the domainjoin args below.");
                logData("Likely args may be: '--notimesync --disable hostname --ou Company/Location'.");
                logData("If you want the help statement, type 'help', and if you want no args, type a space:");
                $djoptions = <STDIN>;
                chomp $djoptions;
                if ($djoptions=~/^\bhelp\b$/i) {
                    runTool($info, $opt, "$info->{lw}->{tools}->{domainjoin} --help", "print");
                    $djoptions = "";
                }
                $opt->{djoptions} = $djoptions;
            }
        }
        if ($djcommand=~/\bjoin\b/) {
            if ($opt->{djdomain}) {
                $domain= $opt->{djdomain};
            }
            while (not $domain) {
                logData("Please enter the domain to join below.");
                $domain= <STDIN>;
                chomp $domain;
                $opt->{djdomain} = $domain;
            }
            if ($opt->{sshuser}) {
                $user = $opt->{sshuser};
            } else {
                logData("Please enter a user to join the domain with here:");
                $user = <STDIN>;
                chomp $user;
                $opt->{sshuser} = $user;
            }
            logData("This tool will now run the following command:");
            logData("$info->{lw}->{tools}->{domainjoin} $djlog $djcommand $djoptions $domain $user");
            logData(" ");
            logData("You will see 2 lines, followed by a blank and a cursor. Please input your password at that point.");
            logData("You will NOT get a newline after entering your password, this is normal.");
            logData(" ");
        }
        runTool($info, $opt, "$info->{lw}->{tools}->{domainjoin} $djlog $djcommand $djoptions $domain $user", "print");
        gatherMemory($info, $opt);
    }
    # Run tests that run every time no matter what

    sectionBreak("lw-get-status");
    runTool($info, $opt, "$info->{lw}->{tools}->{status}", "print");

    sectionBreak("configuration");
    runTool($info, $opt, "$info->{lw}->{tools}->{config}", "print");

    sectionBreak("Running User");
    getUserInfo($info, $opt, $info->{logon});

    sectionBreak("DC Times");
    my $status = runTool($info, $opt, "$info->{lw}->{tools}->{status}", "grep", "Domain:");
    chomp $status;
    my @domains;
    while ($status =~ /DNS Domain:\s+(.*)/g) {
        my $domain=$1;
        sectionBreak("Current DC Time for $domain.");
        $domain=~/[^\s]+$/;
        runTool($info, $opt, "$info->{lw}->{tools}->{dctime} $domain", "print");
        push(@domains, $domain);
    }
    gatherMemory($info, $opt);
    # run optional tests

    if ($opt->{dns}) {
        sectionBreak("DNS Tests");
        my $site = runTool($info, $opt, "$info->{lw}->{tools}->{status}", "grep", 'Site:\s+(.*)');
        my @status = split(/\s+/, $site);
        my (%dclist, %completed);
        foreach my $site (@status) {
            next if ($completed{$site});
            $completed{$site}=1;
            logInfo("We are in site: $site.");
            foreach my $domain (@domains) {
                sectionBreak("DNS Info for $site in $domain.");
                foreach my $search (("_ldap._tcp", "_gc._tcp", "_kerberos._tcp", "_kerberos._udp")) {
                    logData("Results for $search.$domain:");
                    my @records = dnsSrvLookup("$search.$domain");
                    foreach (@records) {
                        logData("  $_");
                        $dclist{$_}=1;
                    }
                    logData("Results for $search.$site._sites.$domain:");
                    @records = dnsSrvLookup("$search.$site._sites.$domain");
                    foreach (@records) {
                        logData("  $_");
                        $dclist{$_}=1;
                    }
                    logData("Results for $search.$site.pdc._msdcs.$domain:");
                    @records = dnsSrvLookup("$search.$site.pdc._msdcs.$domain");
                    foreach (@records) {
                        logData("  $_");
                        $dclist{$_}=1;
                    }
                }
            }
        }
        sectionBreak("Full DC A record list:");
        foreach my $dc (sort(keys(%dclist))) {
            logData(" $dc");
            foreach (dnsLookup($dc, "A")) {
                chomp;
                logData("  $_");
            }
        }
        gatherMemory($info, $opt);
    }
    if ($opt->{users}) {
        sectionBreak("Enum Users");
        runTool($info, $opt, "$info->{lw}->{tools}->{userlist}", "print");
        gatherMemory($info, $opt);
    }
    if ($opt->{groups}) {
        sectionBreak("Enum Groups");
        runTool($info, $opt, "$info->{lw}->{tools}->{grouplist}", "print");
        gatherMemory($info, $opt);
    }

    if ($opt->{ssh}) {
        sectionBreak("SSH Test");
        my $user;
        if ($opt->{sshuser}) {
            $user = $opt->{sshuser};
        } else {
            logData("Testing SSH as an AD user - please enter a username here:");
            $user = <STDIN>;
            chomp $user;
            $opt->{sshuser} = $user;
        }
        $user=safeUsername($user);
        logVerbose("Looking up $user prior to test");
        getUserInfo($info, $opt, $user);
        my $sshcommand = "ssh -vvv -p 22226 -l $user localhost '$opt->{sshcommand}' 2>&1";
        my $sshdcommand = $info->{sshd}->{cmd}." -ddd -p 22226 > $info->{logpath}/sshd-pbis.log 2>&1";
        #$sshdcommand.=$info->{sshd}->{opts}.' 2>&1';

        logData("Running sshd as $sshdcommand");
        my $data1 = System($sshdcommand." & ",1 ,30);
        if ($?) {
            $gRetval |= ERR_SYSTEM_CALL;
            logError("Error launching sshd!");
        } else {
            sleep 1;
            logData("Running ssh as: $sshcommand");
            $data = `$sshcommand`;
            if ($?) {
                $gRetval |= ERR_SYSTEM_CALL;
                logError("Error running ssh as $user!");
            }
        }

        logData($data);
        gatherMemory($info, $opt);
    } elsif ($opt->{sshuser} || $info->{uid} ne "0") {
        my $user = $opt->{sshuser};
        $user = $info->{logon} if (not defined($opt->{sshuser}));
        sectionBreak("User Lookup");
        getUserInfo($info, $opt, $user);
        gatherMemory($info, $opt);
    }

    if ($opt->{performance}) {
        sectionBreak("Performance Tests");
        #my $time = findInPath("time", ["/usr/bin", "/bin", "/usr/local/bin", "/usr/csw/bin", "/usr/sfw/bin"]);
        #if (not $time->{path}) {
        #    logError("Can't run performance testing - can't find 'time' command in: /usr/bin, /bin, /usr/local/bin, /usr/csw/bin, /usr/sfw/bin!!");
        #} else {
        foreach my $flag (("-ln", "-l")) {
            foreach my $dir (("/home", "/tmp", "/var/tmp", "/etc")) {
                logData("# ".scalar(localtime()));
                runTool($info, $opt, "time ls $flag $dir", "print");
            }
        }
        #}
        gatherMemory($info, $opt);
    }

    if ($opt->{gpo}) {
        sectionBreak("GPO Tests");
        runTool($info, $opt, "gporefresh", "print");
        for (my $i = 60; $i<=0; $i-=15) {
            logData("Sleeping $i seconds for full refresh to run...");
            sleep 15;
        }
        gatherMemory($info, $opt);
    }

    if ($opt->{smb}) {
        sectionBreak("SMB Tests");
        #TODO Write
    }

    if ($opt->{sudo}) {
        sectionBreak("Sudo Test");
        logWarning("Opening a bash shell in this window.");
        logWarning("Perform the sudoers tests required, then type 'exit'");
        #TODO Fix this sudoers test not working
        logError("Some output may not print to screen - this is OK");
        my $file = findInPath("bash", ["/bin", "/usr/bin", "/usr/local/bin"]);
        $data = `$file->{path}`;
        logData($data);
        gatherMemory($info, $opt);
    }

    if ($opt->{othertests}) {
        sectionBreak("Other Tests");
        logWarning("Please run any manual tests required now (interactive logon, sudo, su, etc.)");
        logWarning("Type 'done' and hit Enter when complete...");
        my $complete = "";
        while (not ($complete=~/done/i)) {
            $complete=readline(*STDIN);
            chomp $complete;
        }
        gatherMemory($info, $opt);
    }

    if ($opt->{delay}) {
        sectionBreak("Delay for testing");
        logData("Please run any manual tests required now (interactive logon, sudo, su, etc.)");
        logData("This program will continue in $opt->{delaytime} seconds...");
        while ($opt->{delaytime} > 30) {
            $opt->{delaytime} = $opt->{delaytime} - 30;
            sleep 30;
            logData("This program will continue in $opt->{delaytime} seconds...");
            gatherMemory($info, $opt);
        }
        sleep $opt->{delaytime};
    }

    if ($opt->{authtest}) {
        sectionBreak("PAC info");
        my ($logfile, $error);
        $data = "";
        $logfile = $opt->{paclog};
        #$logfile = "$info->{logpath}/$info->{logfile}" if ($opt->{syslog});
        #$logfile = "$info->{logpath}/lsassd.log" if ($opt->{restart} and $opt->{lsassd});
        logWarning("No logfile to read!") unless ($logfile);
        my %sids;
        open(LF, "<$logfile") || logError("Can't open $logfile - $!");
        while(<LF>) {
            if (/PAC (\w+ )?membership is (S-1-5[^\s]+)/) {
                logDebug("Found SID $2");
                $sids{$2} = 1;
            }
        }
        foreach my $sid (sort(keys(%sids))) {
            $data=runTool($info, $opt, "$info->{lw}->{tools}->{findsid} $sid", "return");
            if ($data) {
                logData($data);
                $error = 1;
                $data = "";
            } else {
                logError("Error getting user by SID $sid!");
            }
        }
        close LF;
        logWarning("Couldn't find any PAC information to review") unless ($error);
        gatherMemory($info, $opt);
    }
    if ($opt->{psoutput}) {
        sectionBreak("ps output");
        $data = `$info->{pscmd}`;
        logData($data);
    }
    if ($opt->{memory}) {
        gatherMemory($info, $opt);
        memoryStats($info, $opt);
    }
}

# Main Functions End
#####################################

###########################################
# controller subroutine starts here
sub main() {

    Getopt::Long::Configure('no_ignore_case', 'no_auto_abbrev') || confess;

    my @time = localtime();
    $time[5]+=1900;
    my $datestring = $time[5].sprintf("%02d", $time[4]+1).sprintf("%02d", $time[3]).sprintf("%02d", $time[2]).sprintf("%02d", $time[1]);
    my $info = {};
    $info->{emailaddress} = 'openproject@beyondtrust.com';
    my $host=hostname();

    my $opt = { netlogond => 1,
        users => 1,
        groups => 1,
        lsassd => 1,
        lwiod => 1,
        netlogond => 1,
        gpagentd => 0,
        messages => 1,
        syslog => 1,
        capturefile => "/tmp/pbis-cap",
        captureiface => "",
        loglevel => "info",
        logfile => "/tmp/pbis-support-$host.log",
        tarballdir => "/tmp",
        tarballfile => "pbis-support-$host-$datestring",
        tarballext => ".tar.gz",
        sshcommand => "exit",
        sudocmd => "ls -l /var/lib/pbis/db",
        delaytime => 180,
        gatherdb => 1,
        psoutput => 1,
        djlog => "/var/log/domainjoin-verbose.log",
        pbislevel => "debug",
        alarmtime => "600",
    };

    my $ok = GetOptions($opt,
        'help|h|?',
        'logfile|log|l=s',
        'loglevel|V=s',
        'verbose|v+',
        'tarballdir|t=s',
        'ssh!',
        'gpo|grouppolicy!',
        'gatherdb|db!',
        'dns!',
        'users|u!',
        'groups|g!',
        'sudo!',
        'automounts|autofs!',
        'tcpdump|capture|snoop|iptrace|nettl|c!',
        'capturefile=s',
        'captureiface=s',
        'capturefilter=s',
        'othertests|other|o!',
        'domainjoin|dj!',
        'djcommand=s',
        'djoptions=s',
        'djdomain=s',
        'djlog=s',
        'lsassd|winbindd!',
        'lwiod|lwrdrd|npcmuxd!',
        'netlogond!',
        'gpagentd!',
        'dcerpcd!',
        'eventlogd!',
        'eventfwdd!',
        'lwregd|regdaemon!',
        'lwsmd|svcctl|lwsm|svcctld!',
        'reapsysld|syslogreaper|reaper!',
        'lwscd|smartcard|lwsc!',
        'lwpcks11d|lwpcks11!',
        'lwcertd|lwcert!',
        'autoenrolld|autoenroll!',
        'usermonitor!',
        'pbislevel|pbisloglevel=s',
        'messages!',
        'sambalogs!',
        'restart|r!',
        'syslog!',
        'sshcommand=s',
        'sshuser=s',
        'authtest!',
        'sudopasswd=s',
        'sudocmd=s@',
        'psoutput|ps!',
        'memory|m!',
        'performance|p!',
        'delay!',
        'delaytime|dt=s',
        'cleanup!',
        'alarmtime|alarm=s',
    );
    my $more = shift @ARGV;
    my $errors;

    #now to force some options for tool consistency
    if ($opt->{domainjoin}) {
        $opt->{restart} = 1;
        $opt->{other} = 1;
        $opt->{tcpdump} =1;
    }

    if ($opt->{sudo} or $opt->{ssh} or $opt->{other} or $opt->{delay}) {
        $opt->{authtest} = 1;
    }

    my @requireOptions = qw(logfile );
    foreach my $optName (@requireOptions) {
        if (not $opt->{$optName}) {
            $errors .= "Missing required --".$optName." option.\n";
        }
    }
    if ($more) {
        $errors .= "Too many arguments.\n";
    }
    if ($errors) {
        $gRetval |= ERR_OPTIONS;
        print $errors.usage($opt, $info);
    }

    if (defined($opt->{gpagentd} and $opt->{gpagentd} == 1)) {
        $opt->{gpo} = 1;  #turn on GPO testing since we're doing gpagentd logging.
    }
    if (defined($opt->{gpo} and $opt->{gpo} == 1)) {
        $opt->{gpagentd} = 1;  #turn on GPO testing since we're doing gpagentd logging.
    }

    if (defined($opt->{performance}) and $opt->{performance}) {
        #set specific options because of this kind of test

        # turn on restarts, so that the capture gets readable ldap traffic
        $opt->{restart} = 1;
        $opt->{syslog} = 0;
        $opt->{capture} = 1;
        $opt->{memory} = 1;
        # specifically disable user/group enumeration
        # because we don't want to pre-fill the cache and screw up data analysis
        $opt->{users} = 0;
        $opt->{groups} = 0;
    }

    #if the user has set a "--restart" option, that takes precedence over everything else
    if (not defined $opt->{restart}) {
        $opt->{restart} = 1 if not $opt->{syslog};
        $opt->{restart} = 0 if $opt->{syslog};
    } else {
        $opt->{syslog} = 0 if $opt->{restart};
        $opt->{syslog} = 1 if not $opt->{restart};
    }

    if ($opt->{help} or not $ok) {
        $gRetval |= ERR_OPTIONS;
        print usage($opt, $info);
    }

    exit $gRetval if $gRetval;

    if (defined($opt->{logfile}) && $opt->{logfile} ne "-") {
        open(OUTPUT, ">$opt->{logfile}") || die "can't open logfile $opt->{logfile}\n";
        $gOutput = \*OUTPUT;
        logInfo("Initializing logfile $opt->{logfile}.");
    } else {
        $gOutput = \*STDOUT;
        logInfo("Logging to STDOUT.");
        logError("Will not be able to capture the output log! You should cancel and restart with a different logfile.");
        sleep 5;
    }


    if (defined($opt->{verbose})) {
        $gDebug = $opt->{verbose};
        logData("Logging at level $gDebug");
    }

    if (defined($opt->{loglevel}) && not defined($opt->{verbose})) {
        $gDebug = 5 if ($opt->{loglevel}=~/^debug$/i);
        $gDebug = 4 if ($opt->{loglevel}=~/^verbose$/i);
        $gDebug = 3 if ($opt->{loglevel}=~/^info$/i);
        $gDebug = 2 if ($opt->{loglevel}=~/^warning$/i);
        $gDebug = 1 if ($opt->{loglevel}=~/^error$/i);
        $gDebug = $opt->{loglevel} if ($opt->{loglevel}=~/^\d+$/);
        logWarning("Logging at $opt->{loglevel} level.");
    }
    if ($gDebug<1 or $gDebug > 5) {
        $gDebug = 1 if ($gDebug < 1);
        $gDebug = 5 if ($gDebug > 5);
        logWarning("Log Level previously not properly specified.");
    }


    $opt->{tarballdir}=~s/\/$//;

    unless (-d $opt->{tarballdir}) {
        $gRetval |= ERR_OPTIONS;
        $gRetval |= ERR_FILE_ACCESS;
        logError("$opt->{tarballdir} is not a directory!");
    }


    exit $gRetval if $gRetval;

    sectionBreak("OS Information");
    logDebug("Determining OS info");
    determineOS($info, $opt);

    if (defined($opt->{capturefilter})) {
        $info->{tcpdump}->{filter} = $opt->{capturefilter};
    }

    sectionBreak("PBIS Version");
    logDebug("Determining PBIS version");
    getLikewiseVersion($info, $opt);

    if ($opt->{cleanup}) {
        cleanupaftermyself($info, $opt);
        outputReport($info, $opt);
        exit $gRetval;
    }


    sectionBreak("Options Passed");
    logData(fileparse($0)." version $gVer");
    foreach my $el (keys(%{$opt})) {
        logData("$el = ".&getOnOff($opt->{$el}));
    }

    #TODO support SELinux in Enforcing mode with secontext switches.
    if ((defined $opt->{restart} && $opt->{restart}) && $info->{selinux}) {
        logError("SELinux enforcing mode is *NOT* compatible with the '--restart' option.");
        logError("  Please run 'setenforce 0' before running this tool with the '--restart' option");
        logError("  This tool choses not to run this command for you, to avoid conflicting with corporate policy.");
        logError("  Support may accept the results of this tool with the '--syslog' option instead, which is compatible with Enforcing mode.");
        $gRetval |= ERR_OPTIONS;
        $gRetval |= ERR_OS_INFO;
        exit $gRetval;
    }
    #gatherMemory($info, $opt); # no point gathering stuff before we do restarts, we know the PID will change
    if (defined $opt->{tcpdump} && $opt->{tcpdump}) {
        sectionBreak("Starting tcpdump");
        $info->{scriptstatus}->{tcpdump}=1;
        tcpdumpStart($info, $opt);
    }

    sectionBreak("Daemon restarts");
    logDebug("Turning up logging levels");
    $info->{scriptstatus}->{loglevel}=1;
    if ( $opt->{pbislevel}=~/^(error|warning|verbose|info|debug|trace)$/) {
        changeLogging($info, $opt, $opt->{pbislevel});
    } else {
        changeLogging($info, $opt, "debug");
    }
    logWarning("Sleeping for 120 seconds to let Domains be found");
    waitForDomain($info, $opt);

    runTests($info, $opt);

    sectionBreak("Daemon restarts");
    logDebug("Turning logging levels back to normal");
    changeLogging($info, $opt, "normal");
    $info->{scriptstatus}->{loglevel}=0;

    if (defined $opt->{tcpdump} && $opt->{tcpdump}) {
        sectionBreak("Stopping tcpdump");
        tcpdumpStop($info, $opt);
        $info->{scriptstatus}->{tcpdump}=0;
    }

    outputReport($info, $opt);
}

=head1 (C) BeyondTrust Software

=head1 Description

usage: pbis-support.pl [tests] [log choices] [options]

  This is the BeyondTrust Software PBIS (Open/Enterprise) support tool.
  It creates a log as specified by the options, and creates
  a gzipped tarball in for emailing to the PBIS support team.

  The options are broken into three (3) groups: Tests, Logs,
  and Options.  Any "on/off" flag has a "--no" option available,
  for example: "--nossh" and "--ssh". The "no" obviously
  negates the flag's operation

  Examples:

    pbis-support.pl --ssh --lsassd --nomessages --restart -l pbis.log


=head2 Usage

Tests to be performed:

    --(no)ssh (default = off)
        Test ssh logon interactively and gather logs
    --sshcommand <command> (default = 'exit')
    --sshuser <name> (instead of interactive prompt)
    --(no)gpo --grouppolicy (default = on)
        Perform Group Policy tests and capture Group Policy cache
    -u --(no)users (default = on)
        Enumerate all users
    -g --(no)groups (default = on)
        Enumerate all groups
    --autofs --(no)automounts (default = off)
        Capture /etc/lwi_automount in tarball
    --(no)dns (default = off)
        DNS lookup tests
    -c --(no)tcpdump (--capture) (default = off)
        Capture network traffic using OS default tool
        (tcpdump, nettl, snoop, etc.)
    --capturefile <file> (default = /tmp/pbis-cap)
    --captureiface <iface> (default = )
    --(no)smb (default = off)
        run smbclient against local samba server
    -o --(no)othertests (--other) (default = off)
        Pause to allow other tests (interactive logon,
        multiple ssh tests, etc.) to be run and logged.
    --(no)delay (default = off)
        Pause the script for 180 seconds to gather logging
        data, for example from GUI logons.
    -m --memory (default = off)
        Gather memory utilization statistics to help find/disprove
        memory leaks.
    -p --performance (default = off)
        Run specific set of tests for performance troubleshooting
        of NSS modules and user lookups.
    -dt --delaytime <seconds> (default = 180)
    -dj --domainjoin (default = off)
        Set flags for attempting to join AD, then launch the join interactively
        --djcommand <command>
            command for domainjoin-cli, such as 'join', 'query', 'leave'
        --djoptions <options in quotes>
            Enter domainjoin args such as '--disable hostname --ou AZ/Phoenix/Server'
        --djdomain <domain>
            Name of domain to attempt to join
        --djlog (default = /var/log/domainjoin-verbose.log)
            Path of the domainjoin log.
        Use '--sshuser' for the domainjoin username, or be prompted

   Log choices:

    --(no)lsassd (--winbindd) (default = on)
        Gather lsassd debug logs
    --(no)lwiod (--lwrdrd | --npcmuxd) (default = on)
        Gather lwrdrd debug logs
    --(no)netlogond (default = on)
        Gather netlogond debug logs
    --(no)gpagentd (default = on)
        Gather gpagentd debug logs
    --(no)eventlogd (default = off)
        Gather eventlogd debug logs
    --(no)eventfwdd (default = off)
        Gather eventfwdd debug logs
    --(no)reapsysld (default = off)
        Gather reapsysld debug logs
    --(no)regdaemon (default = off)
        Gather regdaemon debug logs
    --(no)lwsm (default = off)
        Gather lwsm debug logs
    --(no)smartcard (default = off)
        Gather smartcard daemon debug logs
    --(no)certmgr (default = off)
        Gather smartcard daemon debug logs
    --(no)autoenroll (default = off)
        Gather smartcard daemon debug logs
    --pbisloglevel (default = debug)
        What loglevel to run PBIS daemons at (useful for
        long-running captures).
    --(no)messages (default = on)
        Gather syslog logs
    --(no)gatherdb (default = on)
        Gather PBIS Databases
    --(no)sambalogs (default = off)
        Gather logs and config for Samba server
    -ps --(no)psoutput (default = on)
        Gathers full process list from this system
    -m --memory (default = off)

    Options:

    -r --(no)restart (default = off)
        Allow restart of the PBIS daemons to separate logs
    --(no)syslog (default = on)
        Allow editing syslog.conf during the debug run if not
        restarting daemons (exclusive of -r)
    -V --loglevel {error,warning,info,verbose,debug}
        Changes this tool's logging level. (default = info )
    -l --log --logfile <path> (default = /tmp/pbis-support-kubuntu10.log )
        Choose the logfile to write data to.
    -t --tarballdir <path> (default = /tmp )
        Choose where to create the gzipped tarball of log data
    --alarm <seconds> (default = 600 )
        How long to allow tasks to run before they time out
        (sometimes enumerating users or groups can take 10 minutes)

Examples:

pbis-support.pl --ssh --lsassd --nomessages --restart -l pbis.log
pbis-support.pl --restart --regdaemon -c
    Capture a tcpdump or snoop of all daemons starting up
    as well as full logs

=head1 Programmer's data

=head2 Data Structures:

$gRetval is a bitstring used to hold error values.  The small subs at the top ERR_XXX_XXX = { 2;}
are combined with the existing value via bitwise OR operations. This gives us a cumulative count
of the errors that have happened during the run of the program, and a good exit status if non-0

$gDebug is used to determine which level to log at.  higher is more verbose, with 5 being the
current max (debug).

=head3 Defined subroutines are:

usage($opt, $info) - outputs help status with intelligent on/off values based on defaults and flags passed.

changeLogging($info, $opt, $state) - changes logging for all daemons in $opt to $state

changeLoggingByTap($info, $opt, $state) - changes logging using tap-log

changeLoggingBySyslog($info, $opt, $state) - changes daemon log level in $opt if no "tap-log" and syslog logging is in place (not restarting to separte file)

changeLoggingWithLwSm($info, $opt, $state) - called by changeLogging() if LW 6 or greater, to use LWSM for state changes

cleanup() - tries to clean up before exiting, like in failure or ctrl-c - stop tap-log commnads, restart daemons in normal mode, etc.

cleanupaftermyself($info, $opt) - tries to clean up before exiting

daemonRestart($info, $options) - restarts daemon in $options to state in $options

daemonContainerStop($info, $options, $opt) - stops a containerized daemon

daemonContainerStart($info, $options, $opt) - starts a containerized daemon to get startup logs or ldap captures readable

determineOS($info) - updates the $info hash with OS specific paths and commands

dnsLookup($query, $type) - looks up a DNS query of type via dig or nslookup (Net::DNS isn't core)

dnsSrvLookup($lookup) - looks up $lookup via DNS by best means available on system

findInPath($file, $path) searches array REF $path for $file - more detail below

findLogFile($facility) - finds the logfile handling $facility and returns that filename

findProcess($process, $info) returns hash structure of a process' information from PS

gatherMemory($info, $opt) - gathers memory stats in different formats to search for leaks without valgrind available

GetErrorCodeFromChildError($error) - gets error status from child spawned by System();

getLikewiseVersion($info) - determines LW version, sets variables specific to that version, daemon name, tool command, etc.

getOnOff($test) - returns "on" or "off" to boolean $test, returns $test for string/numeric values (non-0/1)

getUserInfo($info, $opt, $name) - gets NSS and PBIS information about $name

killProc($process, $signal, $info) - send any signal to any process by name or PID

killProc2($signal, $process) - sends the actual kill signal to the PID, no name allowed

lineDelete($file, $line) removes $line from $file by commenting out, only if it was added by lineInsert

lineInsert($file, $line) inserts $line to end of $file if not already there.

logData($line) - logs $line regardless of level

logError($line) - logs $line at error (1) level

logWarning($line) - logs $line at warning (2) level or lower

logInfo($line) - logs $line at info (3) level or lower

logVerbose($line) - logs $line at verbose (4) level or lower

logDebug($line) - logs $line at debug (5) level or lower

memoryStats($info, $opt) - does analysis on memory utilization gathered from the gatherMemory() sub.

outputReport($info, $opt) - determines the pieces to gather based on flags

readFile($info, $filename) reads $filename, print to screen and log, parse if neccessary

runTests($info, $opt) - runs the actual tests based on flags

runTool($info, $opt, $tool, $action: $filter) - runs $tool from /opt/pbis/bin directory, performing one of several "actions":
    bury: used to run a tool for its action, rather than its output
    print: used to print a tool's output to screen/log, such as enum-users. Avoids OOM errors for 20k+ user environments.
    return: captures output in an array which is returned to the caller - can generate OOM errors if output is too large.
    grep: search the output for lines which match $filter, returning only those matches in the passed-back array.
        If $filter includes grouping, each line that matches $1 will be returned, rather than the full line

safeRegex($regex) - escape handling for safe regular expression matching in user-input strings.

safeUsername($name) - escape handling for safe username processing in System() calls.

sectionBreak($title) - prints $title as a new section to the log and screen

System($command; $print, $timeout) a system() analogue including child success code handling

tarFiles($info, $opt, $tarball, $file) adds $file to $tarball - creating new $tarball if neccesary

tcpdumpStart($info, $top) - starts tcpdump analogue for the OS

tcpdumpStop($info, $opt) - stops tcpdump analogue for the OS

waitForDomain($info, $opt) - when restarting daemons, waits for domain enumeration to complete, so that reported data is accurate

=head3 Hash Structures

$opt contains each of the command-line options passed.
$info contains information about the system the tool is running on.

=head4 hash REF opt

$opt is a hash reference, with keys as below, grouped for ease of reading (no groups in the hash structure, each key exists at top level):
    (Group: Daemons and logs)
        netlogond
        lsassd
        lwiod
        gpagentd
        eventfwdd
        reapsysld
        lwregd
        lwpcks11d
        lwscd
        lwsmd
        lwcertd
        autoenrolld
        messages
    (Group: Restart Options)
        syslog
        restart
        cleanup
    (Group: Tests to run)
        users
        groups
        gpo
        ssh
        sudo
        othertests
        delay
        authtest
        memory
        performance
        domainjoin
        djoptions (string)
        djdomain (string)
        djcommand (string)
        djlog (string)
    (Group: Extra Info to gather)
        automounts
        tcpdump
        gatherdb
    (Group: file locations and options)
        capturefile (string)
        captureiface (string)
        capturefilter (string)
        loglevel (string or number)
        logfile (string - loglevel and logfile affect screen output, not commands to daemons)
        tarballdir (string)
        tarballfile (string)
        tarballext (string)
        sshcommand (string in case anything other than ssh auth is requested to be tested.  default is "exit")
        sshuser (string, if not entered, program will prompt for one)
    delaytime (number)
        help

=head4 hash REF info

$info is a hash reference, with keys as below. This is a multi-level hash as described below
    OStype (string describing OS: solaris, darwin, linux-rpm, etc.)
    svccontrol (The program calls start/stop as: System($info->{svcctl}->{start1}.$info->{svcctl}->{start2}.$info->{svcctl}->{start3}), allowing OSType to determine startup/shutdown)
        start1 (string: first part of init script to start, like "/etc/init.d/")
        start2 (string: second part of init script to start, like "lsassd")
        start3 (string: 3rd part of init script to start, like " start")
        stop1 (string: first part of init script to stop, like "/etc/init.d/")
        stop2 (string: second part of init script to stop, like "lsassd")
        stop3 (string: 3rd part of init script to stop, like " stop")
        rcpath (string: path to rc scripts: "/etc/rc.d")
    pampath (string: path to pam files or file, "/etc/pam.d")
    logpath (string: path to log files, "/var/log")
    logfile (string: system's default log, such as "messages" or "system.log" )
    nsfile (string: full path to nsswitchc.conf or other)
    timezonefile (string: path to system's timezone information)
    platform (string: like "i386" or similar, removes anything after a "-" as returned from Config{platform})
    osversion (string: "uname -r" output)
    hostname (string: Sys::Hostname::hostname() output)
    uname (string: "uname" output)
    logon (string: login name of user who called the tool (sudo does not mask this))
    name (string: real name of user program is running under (root under sudo))
    uid (number: the effective uidNumber of the user running the program)
    pscmd (string: the command for PS output, since Solaris 10 needs child zones skipped)
    sshd_config (hash reference to "findInPath()" hash value for /etc/sshd_config, or whereever it exists)
        info
        path
        dir
        name
        type
        perm
    krb5conf (hash reference to "findInPath()" hash value for /etc/krb5.conf, or wheereever it exists)
        info
        path
        dir
        name
        type
        perm
    sudoers (hash reference to "findInPath()" hash value for /etc/sudoers, or whereever it exists)
        info
        path
        dir
        name
        type
        perm
    lw (hash reference to Likewise/PBIS-specific information)
        base (string: normally "/opt/pbis")
        path (string: path to bin dir: "/opt/pbis/bin")
        version (string: version of PBIS/Likewise (7.0, 6.5, 6.0, 5.3, 5.1, 4.1))
        smblog (string: name of tool to change smb logging level, which changes from 5.1 to 5.2, doesn't exist previously)
        daemons (hash ref: list of daemons installed)
            smbdaemon (string: name of IO daemon - "lwio", "lwrdr", "npcmuxd")
            authdaemon (string: name of auth daemon - "lsassd" or "winbindd");
            gpdaemon (string: name of group policy daemon "gpagentd" or "centeris.com-gpagentd")
            dcedaemon (string: name of dcerpc endpoint mapper "dcerpcd" or "centeris.com-dcerpcd")
            netdaemon (string: name of netlogon daemon "netlogond" or undef)
            eventlogd (string: name of eventlog daemon "eventlogd or undef)
            eventfwdd (string: name of event forwarder daemon "eventfwdd" or undef)
            syslogreaper (string: name of syslog reaper daemon "reapsysld" or undef)
            registry (string: name of registry daemon "lwregd" or undef)
            lwsm (string: name of service daemon "lwsm" or undef)
            startcmd (string: method to start daemon as daemon from cmd by hand (not via init))
        logging (hash ref: commands for setting up logging)
            command (string for how to change log level live)
            tapcommand (string for tap logging (preferred))
            registry (string for registry commands to change log level for restarts)
        lwsm (hash ref: type of service control)
            control (string: command used to control jobs - "lwsm")
            type (string - "container" "standalone")
            initname (string - path of /etc/init.d/ job for autostart in 6.5)
        tools (hash ref: list of tools available for versioning)
            findsid (string)
            userlist (string)
            grouplist (string)
            userbyname (string)
            userbyid (string)
            groupbyname (string)
            groupbyid (string)
            status (string)
            groupsforuser (string)
            groupsforuid (string)
            regshell (string)
    daemons (hash ref: daemons which have been restarted in debug mode)
        {daemonname} (hash ref: key name may be "netlogond", "lwiod", etc.)
            pid (number: the PID of the daemon launched)
            handle (anonymous ref to the handle used to launch the daemon)
    logedit (hash ref: the file changed if --restart was negated)
        file (findInPath() hash ref)
            info
            path
            dir
            name
            type
            perm
        line (string: the actual line being inserted or commented out)
    tcpdumpfile (string: the location we're storing the tcpdump file we are creationg from the options passed. in $info, rather than $opt, due to centos' funny handling of "pcap" user requiring us to figure out where to store the file)

=head4 findInPath()

findInPath() returns a hash reference with following keys:
    info (array ref: structure from the "stat()" on the file)
    path (string: full path to file)
    dir (string: full path to the dir the file lives in)
    name (string: name of the file itself: "$file->{dir}/$file->{name}" eq "$file->{path}")
    type (character: c,d,f for character, directory, or file)
    perm (character: r,x,w for readable, executable, writable (checked in that order, as writable matters most to our tests. only keep one perm for this test, since stat holds all))

=head4 findProcess()

findProcess() returns a hash reference with the following keys:
    cmd (string: the value of $0 according to "ps -ef" or its OS-specific equivalent)
    bin (string: the best we can determine that the binary name of the process is)
    pid (integer: the PID of the process, for use for killProc2(), for instance)

=cut
