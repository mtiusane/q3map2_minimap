#!/usr/bin/perl
#
# Build map and generate minimap regions based on map brushes with specific texture
#
use strict;
use warnings;
use File::Temp;
use File::Path qw/make_path/;
use File::Find;
use File::Copy;
use File::Basename qw /dirname fileparse/;
use List::Util qw/min max reduce/;
use List::MoreUtils qw/uniq/;

my $INCLUDE_MAP = 1;

# my $minimapMaterial = "combat-t3/minimap-region";
my $unvPath = "$ENV{HOME}/.local/share/unvanquished";
my $unvHome = "$ENV{HOME}/.unvanquished";
my $radiantPath = "$ENV{HOME}/Documents/Programs/netradiant-20150621-ubuntu15-x86_64";
my $q3map2 = "$radiantPath/q3map2.x86_64";

my $longName = "^7Combat ^1T3^7 1.1 / beta1";
my $author = "CU[dragoon]ams";

my $path = shift || die "Syntax: $0 path <args...>";

my $tmp = File::Temp->newdir(
#    CLEANUP => 0
);
my $tmpdir = $tmp->dirname;
my ($mapName,$mapDir,$mapExt) = fileparse($path,qr/\.[^.]*/);
my $mapPath = "$tmpdir/maps/$mapName$mapExt";

print "TMP: $tmpdir\n";
find({
    no_chdir => 1,
    wanted =>  sub {
	if (!/^\./ && !/\~$/ && !/\.(map|prt|srf|bsp)$/ && !/backup|autosave|bak/) {
	    my $sourcePath = "$ENV{PWD}/$File::Find::name";
	    my $targetPath = "$tmpdir/$_";
	    if (-d $sourcePath) {
		# print "Create directory: $targetPath\n";
		# make_path($targetPath);
	    } else {
		make_path(dirname($targetPath));
		# print "Copy $ENV{PWD}/$File::Find::name to $targetPath\n";
		copy($sourcePath, $targetPath) or die $!;
	    }
	}
    }
}, qw/maps scripts meta textures/);
make_path("$tmpdir/maps");
make_path("$tmpdir/minimaps");

# exit;
srand(time);

# print "Writing map file: $mapPath\n";
open FO,'>',$mapPath or die $!;
my $entity = { classname => '', line_fn => sub { $_[0] } };
my $brush;
my @regions;
open FI,'<',$path or die $!;
my $depth = 0;
while (defined(my $line = <FI>)) {
    chomp($line);
    $depth += ($line =~ tr/{/{/) - ($line =~ tr/}/}/);
    if ($depth == 0 && $line =~ /^\s*\/\/\s+entity.*$/) {
	$entity = { classname => '', line_fn => sub { $_[0] } };
	$brush = undef;
	print FO "$line\n";
    } elsif ($depth == 1 && $line =~ /^\s*"classname"\s+"(.+)"\s*$/) {
	$entity->{classname} = $1;
	if ($entity->{classname} eq 'func_group') {
	    my $index = int(rand(8));
	    $entity->{line_fn} = sub { $_[0] =~ s|combat-t3/lightbridge\d*|"combat-t3/lightbridge$index"|re };
	} else {
	    $entity->{line_fn} = sub { $_[0] =~ s|combat-t3/lightbridge\d*|"combat-t3/lightbridge".$brush->{index}|re };
	}
	print FO "$line\n";
    } elsif ($depth >= 1 && $entity->{classname} ne '') {
	if ($depth == 1 && $line =~ /^\s*\/\/\s+brush.+$/) {
	    $brush = { isRegion => 0, lines => [ $line ], planes => [ ], index => int(rand(8)) };
	} elsif ($depth == 1 && $line =~ /^\s*{\s*$/) {
	    push @{$brush->{lines}},$line;
	} elsif ($depth == 1 && $line =~ /^\s*}\s*$/) {
	    unless ($brush->{isRegion}) {
		print FO map { "$_\n" } @{$brush->{lines}};
		print FO "$line\n";
	    } else {
		push @regions,$brush;
	    }
	    $brush = undef;
	} elsif ($depth == 2 && defined($brush)) {
	    if ($line =~ /^\s*\(\s*(?<x0>-?\d+)\s+(?<y0>-?\d+)\s+(?<z0>-?\d+)\s*\)\s+\(\s*(?<x1>-?\d+)\s+(?<y1>-?\d+)\s+(?<z1>-?\d+)\s*\)\s+\(\s*(?<x2>-?\d+)\s+(?<y2>-?\d+)\s+(?<z2>-?\d+)\s*\)\s*combat-t3\/minimap-region\s+.*$/) {
		$brush->{isRegion} = 1;
		push @{$brush->{planes}}, { %+ };
	    } elsif ($line !~ /^\s*$/ && $line !~ /^}$/) {
		$brush->{isRegion} = 0;
	    }
	    push @{$brush->{lines}},$entity->{line_fn}->($line);
	} else {
	    print FO "$line\n";
	}
    } else {
	print FO "$line\n";
    }
}
close FI;
close FO;

# exit;

my @areas = map {
    my $region = $_;
    my @planes;
    foreach my $plane (@{$region->{planes}}) {
	my $v0 = vec3(map { $plane->{$_} } qw/x0 y0 z0/);
	my $v1 = vec3(map { $plane->{$_} } qw/x1 y1 z1/);
	my $v2 = vec3(map { $plane->{$_} } qw/x2 y2 z2/);
	my $a = subtract($v1, $v0);
	my $b = subtract($v2, $v0);
	my $n = normalize(cross($a, $b));
	my $d = dot($n, $v0);
	push @planes,{ normal => $n, distance => $d };
    }
    my @points;
    for(my $i=0;$i<=$#planes+2;++$i)
    {
	my ($i0,$i1,$i2) = ($i % scalar(@planes), ($i + 1) % scalar(@planes), ($i + 2) % scalar(@planes));
	my ($p0,$p1,$p2) = ($planes[$i0], $planes[$i1], $planes[$i2]);
	my ($n0,$d0) = ($p0->{normal},$p0->{distance});
	my ($n1,$d1) = ($p1->{normal},$p1->{distance});
	my ($n2,$d2) = ($p2->{normal},$p2->{distance});
	push @points,divideVF(add(add(multiplyFV(-$d0,cross($n1,$n2)), multiplyFV(-$d1,cross($n2,$n0))), multiplyFV(-$d2,cross($n0,$n1))),dot($n0,cross($n1,$n2)));
    }
    my %min = (
	x => min(map { -$_->{x} } @points),
	y => min(map { -$_->{y} } @points),
	z => min(map { -$_->{z} } @points)
    );
    my %max = (
	x => max(map { -$_->{x} } @points),
	y => max(map { -$_->{y} } @points),
	z => max(map { -$_->{z} } @points)
    );
    { min => \%min, max => \%max };
} @regions;

# print "Total of ",scalar(@areas)," areas\n";

my @edgesX = uniq sort { $a <=> $b } ((map { $_->{min}->{x} } @areas),(map { $_->{max}->{x} } @areas));
my @edgesY = uniq sort { $a <=> $b } ((map { $_->{min}->{y} } @areas),(map { $_->{max}->{y} } @areas));
my @edgesZ = uniq sort { $a <=> $b } ((map { $_->{min}->{z} } @areas),(map { $_->{max}->{z} } @areas));

my @finalAreas;
for(my $i=0;$i<$#edgesX;++$i)
{
    for(my $j=0;$j<$#edgesY;++$j)
    {
	for(my $k=0;$k<$#edgesZ;++$k)
	{
	    my $center = {
		x => 0.5 * ($edgesX[$i] + $edgesX[$i+1]),
		y => 0.5 * ($edgesY[$j] + $edgesY[$j+1]),
		z => 0.5 * ($edgesZ[$k] + $edgesZ[$k+1]),
	    };
	    if (anyAreaContainsPoint(\@areas, $center))
	    {
		push @finalAreas,{
		    min => { x => $edgesX[$i  ], y => $edgesY[$j  ], z => $edgesZ[$k]   },
		    max => { x => $edgesX[$i+1], y => $edgesY[$j+1], z => $edgesZ[$k+1] }
		};
	    }
	}
    }
}

# foreach my $area (@finalAreas) {
#     print "Area: (",join(' ',map { $area->{min}->{$_} } qw/x y z/),") to (",join(' ',map { $area->{max}->{$_} } qw/x y z/),")\n";
# }

run_command("\"$q3map2\" -v -game unvanquished -fs_basepath \"$unvPath\" -fs_homepath \"$unvHome\" -fs_game pkg -meta -custinfoparams $mapPath");
run_command("\"$q3map2\" -v -game unvanquished -fs_basepath \"$unvPath\" -fs_homepath \"$unvHome\" -fs_game pkg -vis -fast -saveprt $mapPath");
run_command("\"$q3map2\" -v -game unvanquished -fs_basepath \"$unvPath\" -fs_homepath \"$unvHome\" -fs_game pkg -light -faster -patchshadows $mapPath");

# run_command("\"$q3map2\" -v -game unvanquished -fs_basepath \"$unvPath\" -fs_homepath \"$unvHome\" -fs_game pkg -meta -custinfoparams -samplesize 8 $mapPath");
# run_command("\"$q3map2\" -v -game unvanquished -fs_basepath \"$unvPath\" -fs_homepath \"$unvHome\" -fs_game pkg -vis -saveprt $mapPath");
# run_command("\"$q3map2\" -v -game unvanquished -fs_basepath \"$unvPath\" -fs_homepath \"$unvHome\" -fs_game pkg -light -fast -shade -dirty -patchshadows -samples 3 -samplesize 8 -bouncegrid -bounce 16 -deluxe -lightmapsize 1024 -external $mapPath");

for(my $i=0;$i<=$#finalAreas;++$i)
{
    my $area = $finalAreas[$i];
    my $minmax = "-minmax $area->{min}->{x} $area->{min}->{y} $area->{min}->{z} $area->{max}->{x} $area->{max}->{y} $area->{max}->{z}";
    run_command("\"$q3map2\" -v -game unvanquished -fs_basepath \"$unvPath\" -fs_homepath \"$unvHome\" -fs_game pkg -minimap -size 1024 -sharpen 1 -border 0 $minmax $mapPath");
    # print "Moving: $tmpdir/maps/$mapName.tga to $tmpdir/maps/$mapName"."_region$i.tga\n";
    move("$tmpdir/maps/$mapName.tga","$tmpdir/minimaps/$mapName"."_region$i.tga") or die $!;
}

unlink("$tmpdir/maps/$mapName.map") unless($INCLUDE_MAP);
unlink("$tmpdir/maps/$mapName.prt");
unlink("$tmpdir/maps/$mapName.srf");

open FO,'>',"$tmpdir/minimaps/$mapName.minimap" or die $!;
print FO "{\n";
for(my $i=0;$i<=$#finalAreas;++$i)
{
    my $area = $finalAreas[$i];
    print FO "\tzone\n";
    print FO "\t{\n";
    print FO "\t\tbounds $area->{min}->{x} $area->{min}->{y} $area->{min}->{z} $area->{max}->{x} $area->{max}->{y} $area->{max}->{z}\n";
    print FO "\t\timage minimaps/$mapName"."_region$i $area->{min}->{x} $area->{min}->{y} $area->{max}->{x} $area->{max}->{y}\n";
    print FO "\t}\n";
}
print FO "}\n";
close FO;

open FO,'>',"$tmpdir/meta/$mapName/$mapName.arena";
print FO "{\n";
print FO "\tmap      \"$mapName\"\n";
print FO "\tlongname \"$longName\"\n";
print FO "\tauthor   \"$author\"\n";
print FO "\ttype     \"tremulous\"\n";
print FO "}\n";
close FO;

open FO,'>',"$tmpdir/DEPS";
print FO "tex-all\n";
close FO;

my $olddir = $ENV{PWD};
chdir $tmpdir;
run_command("zip -r \"$olddir/map-combat-t3_1.1.pk3\" .");
chdir $olddir;

sub anyAreaContainsPoint {
    my ($areas,$point) = @_;
    foreach my $area (@$areas) {
	if (areaContainsPoint($area,$point))
	{
	    return 1;
	}
    }
    return 0;
}

sub areaContainsPoint {
    my ($area,$point) = @_;
    return
	$area->{min}->{x} <= $point->{x} && $area->{min}->{y} <= $point->{y} && $area->{min}->{z} <= $point->{z} &&
	$area->{max}->{x} >= $point->{x} && $area->{max}->{y} >= $point->{y} && $area->{max}->{z} >= $point->{z};
}

sub vec3 {
    my ($x,$y,$z) = @_;
    return { x => $x, y => $y, z => $z };
}

sub cross {
    my ($a,$b) = @_;
    return {
	x => $a->{y} * $b->{z} - $a->{z} * $b->{y},
	y => $a->{z} * $b->{x} - $a->{x} * $b->{z},
	z => $a->{x} * $b->{y} - $a->{y} * $b->{x}
    };
}

sub dot
{
    my ($a,$b) = @_;
    return $a->{x} * $b->{x} + $a->{y} * $b->{y} + $a->{z} * $b->{z};
}

sub add
{
    my ($a,$b) = @_;
    return { x => $a->{x} + $b->{x}, y => $a->{y} + $b->{y}, z => $a->{z} + $b->{z} };
}

sub subtract
{
    my ($a,$b) = @_;
    return { x => $a->{x} - $b->{x}, y => $a->{y} - $b->{y}, z => $a->{z} - $b->{z} };
}

sub negate
{
    my ($a) = @_;
    return { x => -$a->{x}, y => -$a->{y}, z => -$b->{z} };
}

sub sqrMagnitude
{
    my ($a) = @_;
    return dot($a,$a);
}

sub magnitude
{
    my ($a) = @_;
    return sqrt(sqrMagnitude($a));
}

sub multiplyFV
{
    my ($a,$b) = @_;
    return vec3($a * $b->{x}, $a * $b->{y}, $a * $b->{z});
}

sub divideVF
{
    my ($a,$b) = @_;
    return multiplyFV(1.0 / $b, $a);
}

sub normalize
{
    my ($a) = @_;
    my $d = magnitude($a);
    return vec3($a->{x} / $d, $a->{y} / $d, $a->{z} / $d);
}

sub run_command
{
    my ($command) = @_;
    print "$command\n";
    system $command;
}
