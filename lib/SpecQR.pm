package SpecQR;
use 5.026;
use strict;
use warnings;
use Exporter 'import';
our $VERSION='0.1.0';
use SpecQR::API ();
use SpecQR::Segments ();
use SpecQR::Render ();
use SpecQR::GS1 ();
use SpecQR::StructuredAppend ();
our (@EXPORT_OK,%EXPORT_TAGS);
BEGIN {
    my %groups=(
        qr => ['SpecQR::API',qw(generate generate_segments plan plan_segments estimate analyze_segments get_capacity diagnostics size module_at)],
        segments => ['SpecQR::Segments',qw(new_segment byte_segment numeric alphanumeric kanji eci fnc1 fnc1_second structured_append_segment)],
        render => ['SpecQR::Render',qw(to_svg to_png to_pixels to_svg_data_url to_png_data_url render_dimensions)],
        gs1 => ['SpecQR::GS1'],
        structured_append => ['SpecQR::StructuredAppend',qw(calculate_structured_append_parity calculate_structured_append_segments_parity generate_structured_append generate_segments_structured_append merge_structured_append_parts)]
    );
    # Names resolve only to this edition's native Perl modules.
    $groups{segments}=[ 'SpecQR::Segments',qw(new_segment byte_segment numeric alphanumeric kanji eci fnc1 fnc1_second structured_append_segment) ];
    $groups{gs1}=[ 'SpecQR::GS1',@SpecQR::GS1::EXPORT_OK ];
    no strict 'refs';
    for my $group (sort keys %groups) {
        my($package,@names)=@{$groups{$group}};
        for my $name (@names) { next if $name =~ /^[\@\%]/; *{$name}=\&{"${package}::$name"}; push @EXPORT_OK,$name; push @{$EXPORT_TAGS{$group}},$name; }
    }
    $EXPORT_TAGS{all}=[@EXPORT_OK];
}
1;
