#!/usr/bin/env perl
#
#-------------------------------------------------------------------------------
# Copyright (c) 2014-2017 René Just, Darioush Jalali, and Defects4J contributors.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#-------------------------------------------------------------------------------

=pod

=head1 NAME

fix_test_suite.pl -- remove failing tests from test suite until all tests pass.

=head1 SYNOPSIS

  fix_test_suite.pl -p project_id -d suite_dir [-f include_file_pattern] [-v version_id] [-s test_suite_src] [-t tmp_dir] [-A] [-D]

=head1 OPTIONS

=over 4

=item -p C<project_id>

The id of the project for which the generated test suites are analyzed.
See L<Project|Project/"Available Project IDs"> module for available project IDs.

=item -d F<suite_dir>

The directory that contains the test suite archives.
See L<Test suites|/"Test suites">.

=item -f C<include_file_pattern>

The pattern of the file names of the test classes that should be included (optional).
Per default all files (*.java) are included.

=item -v C<version_id>

Only analyze test suites for this version id (optional). Per default all
test suites for the given project id are analyzed.

=item -s C<test_suite_src>

Only analyze test suites originating from this source (optional).
A test suite source is a specific tool or configuration (e.g., evosuite-branch).
Per default all test suite sources for the given project id are considered.

=item -t F<tmp_dir>

The temporary root directory to be used to check out program versions (optional).
The default is F</tmp>.

=item -A

Assertions: Try to remove failing assertions first, before removing the entire
test method (optional). By default failing test methods are entirely removed.

=item -D

Debug: Enable verbose logging and do not delete the temporary check-out directory
(optional).

=back

=head1 DESCRIPTION

Runs the following worflow for each provided test suite (i.e., each test suite
archive in F<suite_dir>):

=over 4

=item 1) Remove uncompilable test classes until the test suite compiles.

=item 2) Run test suite and monitor failing tests -- remove failing test methods
         and repeat until:


=over 4

=item * The entire test suite passes 5 times in a row.

=cut
my $RUNS = 5;

=pod

=item * Each test method passes in isolation (B<TODO: not yet implemented!>).

=back

=back

If a test suite was fixed, its original archive is backed up and replaced with
the fixed version.

=cut
use warnings;
use strict;

use FindBin;
use File::Basename;
use Cwd qw(abs_path);
use Getopt::Std;
use Pod::Usage;

use lib abs_path("$FindBin::Bin/../core");
use Constants;
use Project;
use Utils;
use Log;

#
# Process arguments and issue usage message if necessary.
#
my %cmd_opts;
getopts('p:d:v:s:t:f:AD', \%cmd_opts) or pod2usage(1);

pod2usage(1) unless defined $cmd_opts{p} and defined $cmd_opts{d};

my $SUITE_DIR = abs_path($cmd_opts{d});
my $PID = $cmd_opts{p};
my $VID = $cmd_opts{v} if defined $cmd_opts{v};
my $TEST_SRC = $cmd_opts{s} if defined $cmd_opts{s};
my $INCL = $cmd_opts{f} // "*.java";
my $RM_ASSERTS = defined $cmd_opts{A} ? 1 : 0;
# Enable debugging if flag is set
$DEBUG = 1 if defined $cmd_opts{D};

# Check format of target version id
if (defined $VID) {
    Utils::check_vid($VID);
}
=pod

=head2 Test Suites

To be considered for the analysis, a test suite has to be provided as an archive in
F<suite_dir>. Format of the archive file name:

C<project_id-version_id-test_suite_src(\.test_id)?\.tar\.bz2>

Note that C<test_id> is optional, the default is 1.

Examples:

=over 4

=item * F<Lang-11f-randoop.1.tar.bz2 (equal to Lang-1-randoop.tar.bz2)>

=item * F<Lang-11b-randoop.2.tar.bz2>

=item * F<Lang-12b-evosuite-weakmutation.1.tar.bz2>

=item * F<Lang-12f-evosuite-branch.1.tar.bz2>

=back

=cut
my @list;
opendir(DIR, $SUITE_DIR) or die "Could not open directory: $SUITE_DIR!";
my @entries = readdir(DIR);
closedir(DIR);
foreach (@entries) {
    next unless /^([^-]+)-(\d+[bf])-([^\.]+)(\.(\d+))?\.tar\.bz2$/;
    my $pid = $1;
    my $vid = $2;
    my $src = $3;
    my $tid = ($5 or "1");
    # Check whether target pid matches
    next if ($PID ne $pid);
    # Check whether a target src is defined
    next if defined($TEST_SRC) and ($TEST_SRC ne $src);
    # Check whether a target version_id is defined
    next if defined($VID) and ($VID ne $vid);

    push (@list, {name => $_, pid => $pid, vid=>$vid, src=>$src, tid=>$tid});
}

# Set up project
my $TMP_DIR = Utils::get_tmp_dir($cmd_opts{t});
system("mkdir -p $TMP_DIR");


=pod

=head2 Logging

This script logs all information to fix_tests.log in the test suite directory
F<SUITE_DIR>.

=cut
my $LOG = Log::create_log("$SUITE_DIR/fix_test_suite.log");

# Line separator
my $sep = "-"x80;

# Log current time
$LOG->log_time("Start fixing tests");
$LOG->log_msg("- Found " . scalar(@list) . " test archive(s)");

suite: foreach (@list) {
    my $name = $_->{name};
    my $pid  = $_->{pid};
    my $vid  = $_->{vid};
    my $src  = $_->{src};
    my $project = Project::create_project($pid);
    $project->{prog_root} = $TMP_DIR;

    printf ("$sep\n$name\n$sep\n");

    $project->checkout_vid($vid);

    # Extract generated tests into temp directory
    Utils::extract_test_suite("$SUITE_DIR/$name", "$TMP_DIR/$src")
        or die "Cannot extract test suite!";

    # Counter for successful runs of fixed test suite
    my $counter = $RUNS;

    my $fixed = 0;
    while ($counter > 0) {
        # Compile generated tests
        my $comp_log = "$TMP_DIR/comp_tests.log";
        if (! $project->compile_ext_tests("$TMP_DIR/$src", $comp_log)) {
            $LOG->log_file(" - Tests do not compile: $name", $comp_log);
            _rm_classes($comp_log, $src, $name);
            # Indicate that test suite changed
            $fixed = 1;
            next;
        }

        # Temporary log file to monitor failing tests
        my $tests = "$TMP_DIR/run_tests.log";

        # Check for errors of runtime system
        `>$tests`;
        if (! $project->run_ext_tests("$TMP_DIR/$src", "$INCL", $tests)) {
            $LOG->log_file(" - Tests not executable: $name", $tests);
            next suite;
        }

        # Check failing test classes and methods
        my $list = Utils::get_failing_tests($tests) or die;
        if (scalar(@{$list->{classes}}) != 0) {
            $LOG->log_msg(" - Failing test classes: $name");
            $LOG->log_msg(join("\n", @{$list->{classes}}));
            $LOG->log_msg("Failing test classes are NOT automatically removed!");
            $LOG->log_file("Stack traces:", $tests);
            #
            # TODO: Automatically remove failing test classes?
            #
            # This should be fine for generated test suites as
            # there are usually no compilation dependencies
            # between the individual test classes.
            #
            # However, a failing test class most probably indicates
            # a configuration issue, which should be fixed before
            # any broken test is removed.
            #
#            if (scalar(@{$list->{classes}}) != 0) {
#                foreach my $class (@{$list->{classes}}) {
#                    my $file = $class;
#                    $file =~ s/\./\//g;
#                    $file = "$TMP_DIR/$src/$file.java";
#                    system("mv $file $file.broken") == 0 or die "Cannot rename broken test class";
#                }
#                # Indicate that test suite changed
#                $fixed = 1;
#                next;
#            }
            next suite;
        }

        # No failing methods -> decrease counter and continue iteration
        if (scalar(@{$list->{methods}}) == 0) {
            --$counter;
            next;
        } else {
            # Reset counter and fix tests
            $counter = $RUNS;
            # Indicate that test suite changed
            $fixed = 1;
            $LOG->log_file(" - Removing " . scalar(@{$list->{methods}}) . " test methods: $name", $tests);
            system("export D4J_RM_ASSERTS=$RM_ASSERTS && $UTIL_DIR/rm_broken_tests.pl $tests $TMP_DIR/$src") == 0 or die "Cannot remove broken test method";
        }
    }

    # TODO: Run test classes in isolation

    if ($fixed) {
        # Back up archive if necessary
        system("mv $SUITE_DIR/$name $SUITE_DIR/$name.bak") unless -e "$SUITE_DIR/$name.bak";
        system("cd $TMP_DIR/$src && tar -cjf $SUITE_DIR/$name *");
    }
}
# Log current time
$LOG->log_time("End fixing tests");
$LOG->close();

# Clean up
system("rm -rf $TMP_DIR") unless $DEBUG;

#
# Remove uncompilable test cases based on the compiler's log (if there
# is any issue non-related to any test case, the correspondent source
# file is removed)
#
sub _rm_classes {
    my ($comp_log, $src, $name) = @_;
    open(LOG, "<$comp_log") or die "Cannot read compiler log!";
    $LOG->log_msg(" - Removing uncompilable test cases from: $name");
    my @uncompilable_tests = ();
    while (<LOG>) {
        my $removed = 0;

        # Find file names in javac's log: [javac] "path"/"file_name".java:"line_number": error: "error_text"
        next unless /javac.*($TMP_DIR\/$src\/(.*\.java)):(\d+):.*error/;
        my $file = $1;
        my $class = $2;
        my $line_number = $3;

        # Skip already removed files
        next unless -e $file;

        $class =~ s/\.java$//;
        $class =~ s/\//\./g;

        # To which test method does the uncompilable line belong?
        open(JAVA_FILE, $file) or die "Cannot open '$file' file!";
        my $test_name = "";
        my $line_index = 0;
        while (<JAVA_FILE>) {
            ++$line_index;
            next unless /public\s*void\s*(test.*)\s*\(\s*\).*/;
            my $t_name = $1;

            if ($line_index > $line_number) {
              $LOG->log_msg($t_name);
              last;
            }

            $test_name = $t_name;
            $removed = 1;
        }
        close(JAVA_FILE);

        if (! $removed) {
          # in case of compilation issues due to, for example, wrong
          # or non-existing imported classes, or problems with any
          # super class, the source file is removed
          $LOG->log_msg($class);
          system("mv $file $file.broken") == 0 or die "Cannot rename uncompilable source file";

          # get rid of all test cases of this class that have been
          # selected to be removed
          @uncompilable_tests = grep ! /^--- $class::/, @uncompilable_tests;
        } else {
          # e.g., '--- org.foo.BarTest::test09'
          my $test_canonical_name = "--- $class::$test_name";
          # Skip already selected (to be removed) test cases
          if (! grep{/^$test_canonical_name$/} @uncompilable_tests) {
            push(@uncompilable_tests, $test_canonical_name);
          }
        }
    }
    close(LOG);

    if (scalar(@uncompilable_tests) > 0) {
      # Write to a file the name of all uncompilable test cases (one per
      # line) and call 'rm_broken_tests.pl' to remove all of them
      my $uncompilable_tests_file_path = "$TMP_DIR/uncompilable-test-cases.txt";
      open my $uncompilable_tests_file, ">$uncompilable_tests_file_path" or die $!;
      print $uncompilable_tests_file join("\n", @uncompilable_tests);
      close($uncompilable_tests_file);

      $LOG->log_file(" - Removing " . scalar(@uncompilable_tests) . " uncompilable test case(s):", $uncompilable_tests_file_path);
      system("export D4J_RM_ASSERTS=$RM_ASSERTS && $UTIL_DIR/rm_broken_tests.pl $uncompilable_tests_file_path $TMP_DIR/$src") == 0 or die "Cannot remove broken test method(s)";
    }
}
