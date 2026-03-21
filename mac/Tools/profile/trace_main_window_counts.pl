#!/usr/bin/env perl
use strict;
use warnings;

my $xml = shift @ARGV;
my $start_ns = shift @ARGV;
my $end_ns = shift @ARGV;

if (!defined $xml || !defined $start_ns) {
    die "usage: $0 /path/to/time_profile_table.xml START_NS [END_NS]\n";
}
$end_ns = 9_223_372_036_854_775_807 if !defined $end_ns;

my @patterns = (
    ["ui_trackpad_surface", qr/TrackpadSurfaceView\./],
    ["ui_draw_main", qr/TrackpadSurfaceView\.draw\(_:\)/],
    ["ui_draw_labels", qr/drawGridLabels/],
    ["ui_draw_centered_text", qr/drawCenteredText/],
    ["ag_subgraph_update", qr/AG::Subgraph::update\(/],
    ["ag_graph_update_stack", qr/AG::Graph::UpdateStack::update\(/],
    ["ca_context_commit", qr/CA::Context::commit_transaction/],
    ["dispatch_main_queue", qr/_dispatch_main_queue_drain/],
    ["runloop", qr/__CFRunLoopRun/],
);

my (%frame_name, %thread_fmt, %bt_tokens, %has, @rows);
my $total = 0;

open my $fh, '<', $xml or die "failed to open $xml: $!\n";
while (my $line = <$fh>) {
    while ($line =~ /<thread id="(\d+)" fmt="([^"]+)"/g) {
        $thread_fmt{$1} //= $2;
    }
    while ($line =~ /<frame id="(\d+)" name="([^"]+)"/g) {
        $frame_name{$1} //= $2;
    }

    next if $line !~ /<row>/;

    my ($time) = $line =~ /<sample-time[^>]*>(\d+)<\/sample-time>/;
    my ($thread_id) = $line =~ /<thread id="(\d+)"/;
    my ($thread_ref) = $line =~ /<thread ref="(\d+)"/;
    my $thread = defined($thread_ref) ? $thread_ref : $thread_id;

    my ($bid) = $line =~ /<backtrace id="(\d+)"/;
    my ($bref) = $line =~ /<backtrace ref="(\d+)"/;
    my $bt = defined($bref) ? $bref : $bid;

    if (defined($time) && $time >= $start_ns && $time <= $end_ns) {
        my $fmt = defined($thread) ? ($thread_fmt{$thread} // '') : '';
        if ($fmt =~ /Main Thread/) {
            $total++;
            push @rows, $bt;
        }
    }

    if (defined $bid && $line =~ /<backtrace id="\d+"[^>]*>(.*?)<\/backtrace>/) {
        my $inner = $1;
        my @tokens = ($inner =~ /<frame (?:id|ref)="(\d+)"/g);
        $bt_tokens{$bid} = \@tokens if @tokens;
    }
}
close $fh;

for my $bid (keys %bt_tokens) {
    my @names = map { $frame_name{$_} // () } @{ $bt_tokens{$bid} };
    for my $p (@patterns) {
        my ($label, $re) = @$p;
        for my $n (@names) {
            if ($n =~ $re) {
                $has{$label}{$bid} = 1;
                last;
            }
        }
    }
}

print "window_start_ns\t$start_ns\n";
print "window_end_ns\t$end_ns\n";
print "main_window_rows\t$total\n";
for my $p (@patterns) {
    my ($label, $re) = @$p;
    my $count = 0;
    for my $bt (@rows) {
        $count++ if defined($bt) && $has{$label}{$bt};
    }
    printf "%s\t%d\t%.2f%%\n", $label, $count, ($total ? 100.0 * $count / $total : 0);
}
