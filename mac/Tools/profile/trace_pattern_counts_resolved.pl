#!/usr/bin/env perl
use strict;
use warnings;

my $xml = shift @ARGV;
if (!defined $xml) {
    die "usage: $0 /path/to/time_profile_table.xml\n";
}

my @patterns = (
    ["ui_trackpad_surface", qr/TrackpadSurfaceView\./],
    ["ui_draw_main", qr/TrackpadSurfaceView\.draw\(_:\)/],
    ["ui_draw_labels", qr/drawGridLabels/],
    ["ui_draw_sensor_grid", qr/drawSensorGrid/],
    ["ui_draw_centered_text", qr/drawCenteredText/],
    ["ui_draw_touches", qr/drawTouches/],
    ["engine_process_runtime", qr/TouchProcessorEngine\.processRuntimeRawFrame/],
    ["engine_update_intent_global", qr/TouchProcessorEngine\.updateIntentGlobal/],
    ["engine_bindings", qr/TouchProcessorEngine\.bindings\(for/],
    ["runtime_ingest", qr/RuntimeRenderSnapshotService\.ingest/],
    ["status_poll", qr/RuntimeStatusVisualsService\.startPolling/],
    ["status_snapshot", qr/EngineActorBoundary\.statusSnapshot/],
    ["asyncstream_yield", qr/AsyncStream\.Continuation\.yield/],
    ["array_make_mutable", qr/Array\._makeMutableAndUnique/],
    ["contentview_trackpaddeck", qr/ContentView\.TrackpadDeckView/],
    ["contentview_right_sidebar", qr/ContentView\.rightSidebarView\.getter/],
    ["oms_emit_raw", qr/OMSManager\.emitRawTouchFrame/],
    ["openmt_raw_callback", qr/OpenMTManager handleRawFrameWithDevice/],
    ["ag_subgraph_update", qr/AG::Subgraph::update\(/],
    ["ag_graph_update_stack", qr/AG::Graph::UpdateStack::update\(/],
    ["ca_fill_lines", qr/CA::OGL::Shape::FillRenderer::render_lines/],
    ["ca_context_commit", qr/CA::Context::commit_transaction/],
    ["dispatch_root_queue_drain", qr/_dispatch_root_queue_drain/],
);

my (%frame_name, %bt_tokens, %has, @rows);
my $total = 0;

open my $fh, '<', $xml or die "failed to open $xml: $!\n";
while (my $line = <$fh>) {
    while ($line =~ /<frame id="(\d+)" name="([^"]+)"/g) {
        $frame_name{$1} //= $2;
    }

    next if $line !~ /<row>/;
    $total++;

    my ($bid) = $line =~ /<backtrace id="(\d+)"/;
    my ($bref) = $line =~ /<backtrace ref="(\d+)"/;
    my $bt = defined($bref) ? $bref : $bid;
    push @rows, $bt;

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

print "total_rows\t$total\n";
for my $p (@patterns) {
    my ($label, $re) = @$p;
    my $count = 0;
    for my $bt (@rows) {
        $count++ if defined($bt) && $has{$label}{$bt};
    }
    printf "%s\t%d\t%.2f%%\n", $label, $count, ($total ? 100.0 * $count / $total : 0);
}
