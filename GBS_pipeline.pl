#!/usr/bin/perl -w

##### GBS_pipeline.pl - a multi-step pipeline for GBS analysis #####
##### Usage: ./GBS_pipeline.pl [function] [arg1] [arg2] ...
##### Functions:
#####   function1 population barcode_file re_site read1_file read2_file output_dir
#####   function2 trimmomatic_path trim_file
#####   function3 bowtie2_dir reference_genome [-- options]
#####   function4 samtools_dir bcftools_dir
##### Requirements:
#####   Trimmomatic (v0.17-0.33), Bowtie2 (v2.x.x), SAMtools (v1.x), BCFtools (v1.x)
#####   A file listing barcodes (indices) for demultiplexing (optionally, each barcode associated with a sample name)
#####   Paired read data in separate FASTQ files (R1 reads and R2 reads)
#####   A file containing adaptor and other sequences for trimming purposes
#####   A FASTA file containing the reference genome
##### See the perldoc for a full description: perldoc GBS_Pipeline.pl
#####   or refer to: github.com/carolyncaron/GBSpipeline/wiki/Using-GBSpipeline-for-the-first-time
#####   for a tutorial.

use strict;
use warnings;
use File::Basename;
use IO::File;
use feature qw/switch/;
use Time::HiRes;
use FindBin qw($Bin);
use IPC::Cmd qw[run];
use Pod::Usage;
use Data::Dumper;

#######################
##### GET OPTIONS #####
#######################

# Check if command line flags were provided: this overrides any non-flag options
use Getopt::Long;

my ( $config_file, $help );
GetOptions ('c|config=s' => \$config_file,
            'help' => \$help,
           );

pod2usage(-verbose => 2) if $help;

#######################
##### CONFIG FILE #####
#######################

my $CONFIG_FILE;

# Check for the presence of a config file, otherwise assume it is named "GBS.conf"
unless ( $config_file ) {   $config_file = "./GBS.conf";    }

# Parse configuration file into a hash
my %config_hash;
open CONFIG, "<$config_file" or die "ERROR: Unable to open config file $CONFIG_FILE\n";
while (<CONFIG>)
{
    chomp;
    s/#.*//; # Remove comments
    s/^\s+//; # Remove opening whitespace
    s/\s+$//;  # Remove closing whitespace
    next unless length;
    my ($key, $value) = split(/\s*=\s*/, $_, 2);
    $config_hash{$key} = $value;
}

################
##### MAIN #####
################
# Check for user-specified functions to run- if none specified, display POD #

# Check that at least one argument is given
if ( exists ( $ARGV[0] ) )
{
    my $FUNCTION = $ARGV[0];
    shift @ARGV;
    my @args = @ARGV;
    my $num_args = $#args + 1;

    my $start = Time::HiRes::gettimeofday();

    # Regardless of the function specified, each function requires access to these parameters:
    # population, index_file and output_dir
    my ( $population, $index_file, $output_dir, $reference_genome );

    if ($num_args == 0)
    {
        if ($config_hash{'POPULATION'}) { $population = $config_hash{'POPULATION'}; }
            else { report_missing('POPULATION'); }
        if ($config_hash{'INDEX_FILE'}) { $index_file = $config_hash{'INDEX_FILE'}; }
            else { report_missing('INDEX_FILE'); }
        if ($config_hash{'READS_DIR'})  { $output_dir = $config_hash{'READS_DIR'};  }
            else { report_missing('READS_DIR'); }
    }
    # Grab them from the recently created config file from step 1 (or step 3 for reference genome)
    # Note that we don't need these to be non-empty, since this may be the first step and they will
    # be provided at that time.
    else
    {
        chomp($population = `grep 'POPULATION' $config_file | cut -d'=' -f2`);
        chomp($index_file = `grep 'INDEX_FILE' $config_file | cut -d'=' -f2`);
        chomp($output_dir = `grep 'READS_DIR' $config_file | cut -d'=' -f2`);
        chomp($reference_genome = `grep 'REFERENCE' $config_file | cut -d'=' -f2`);
    }

    # Call the appropriate function
    given($FUNCTION)
    {
        ##### DEMULTIPLEX #####
        when ( /function1/ || /f1/ || /demultiplex/ )
        {
            print "Calling $FUNCTION ...\n";
            my ( $RE_site, $R1_file, $R2_file );

            # Check config file for parameters
            if ($num_args == 0)
            {
                if ($config_hash{'RE_SITE'})    { $RE_site    = $config_hash{'RE_SITE'};    }
                    else { $RE_site = ''; }
                if ($config_hash{'R1_FILE'})    { $R1_file    = $config_hash{'R1_FILE'};    }
                    else { report_missing('R1_FILE'); }
                if ($config_hash{'R2_FILE'})    { $R2_file    = $config_hash{'R2_FILE'};    }
                    else { report_missing('R2_FILE'); }
            }
            # Else, parameters are provided via command line
            elsif ($num_args == 6)
            {
                $population = $args[0];
                $index_file = $args[1];
                $RE_site    = $args[2];
                $R1_file    = $args[3];
                $R2_file    = $args[4];
                $output_dir = $args[5];

                # Save the sample and index file into the configuration file
                add_to_config("POPULATION", $population, "The generic name used for this population");
                add_to_config("INDEX_FILE", $index_file, "The filename of the list of indices (aka barcodes)");
                add_to_config("READS_DIR", $output_dir, "The location where output of processed reads are placed");
            }
            # No config file or parameters!
            else
            {
                print "ERROR: Unexpected number of parameters given ($num_args). Program will exit.\n";
                die "Try ./GBS_pipeline.pl -help for options.\n";
            }

            require "$Bin/GBS_function1.pl";
            function1($population, $index_file, $RE_site, $R1_file, $R2_file, $output_dir);

            summarize($start);
        }

        ##### TRIM READS #####
        when ( /function2/ || /f2/ || /trim_reads/ || /trim/ )
        {
            print "Calling $FUNCTION ...\n";
            my ( $trimmomatic_path, $trim_file, %trim_options );

            # Check config file for parameters
            if ($num_args == 0)
            {
                if ($config_hash{'TRIMMOMATIC_PATH'}) { $trimmomatic_path = $config_hash{'TRIMMOMATIC_PATH'}; }
                    else { report_missing('TRIMMOMATIC_PATH'); }
                if ($config_hash{'TRIM_FILE'}) { $trim_file = $config_hash{'TRIM_FILE'}; }
                    else { report_missing('TRIM_FILE'); }

                # Save options for Trimmomatic in a hash
                %trim_options = map { $_ => $config_hash{$_} } qw/TRIM_THREADS SEED_MISMATCHES PALINDROME_CLIP_THRESHOLD SIMPLE_CLIP_THRESHOLD WINDOW_SIZE REQUIRED_QUALITY LEADING_QUALITY TRAILING_QUALITY MINLEN/;
            }
            # Check for parameters on command line
            elsif ($num_args == 2)
            {
                $trimmomatic_path = $args[0];
                $trim_file = $args[1];
            }
            else
            {
                print "ERROR: Unexpected number of parameters given ($num_args). Program will exit.\n";
                die "Try ./GBS_pipeline.pl -help for options.\n";
            }

            require "$Bin/GBS_function2.pl";
            f2($trimmomatic_path, $trim_file, $population, $index_file, $output_dir, \%trim_options);

            summarize($start);
        }

        ##### ALIGN READS #####
        when ( /function3/ || /f3/ || /align_reads/ || /align/ )
        {
            print "Calling $FUNCTION ...\n";
            my ( $bowtie2_dir, %align_options );

            # Check config file for parameters
            if ($num_args == 0)
            {
                if ($config_hash{'BOWTIE2_PATH'}) { $bowtie2_dir = $config_hash{'BOWTIE2_PATH'}; }
                    else { report_missing('BOWTIE2_PATH'); }
                if ($config_hash{'REFERENCE'}) { $reference_genome = $config_hash{'REFERENCE'}; }
                    else { report_missing('REFERENCE'); }

                # Save options for Bowtie2 in a hash
                %align_options = map { $_ => $config_hash{$_} } qw/ALIGN_THREADS MAX_VALID_ALIGNMENTS MAX_FRAGMENT_LENGTH MAX_RESEED_RATE/;
            }
            # Check for parameters on command line
            elsif ($num_args == 2)
            {
                $bowtie2_dir = $args[0];
                $reference_genome = $args[1];
                add_to_config("REFERENCE",$reference_genome,"The pathname of the reference genome sequence.");
            }
            else
            {
                print "ERROR: Unexpected number of parameters given ($num_args). Program will exit.\n";
                die "Try ./GBS_pipeline.pl -help for options.\n";
            }

            require "$Bin/GBS_function3.pl";
            f3($bowtie2_dir, $reference_genome, $population, $index_file, $output_dir, \%align_options);

            summarize($start);
        }

        ##### SNP CALLING #####
        when ( /function4/ || /f4/ || /SNP_calling/ || /call_SNPs/ )
        {
            print "Calling $FUNCTION ...\n";
            my ( $samtools_dir, $bcftools_dir );

            # Check config file for parameters
            if ($num_args == 0)
            {
                if ($config_hash{'SAMTOOLS_PATH'}) { $samtools_dir = $config_hash{'SAMTOOLS_PATH'}; }
                    else { report_missing('SAMTOOLS_PATH'); }
                if ($config_hash{'BCFTOOLS_PATH'}) { $bcftools_dir = $config_hash{'BCFTOOLS_PATH'}; }
                    else { $bcftools_dir = $samtools_dir; }
                if ($config_hash{'REFERENCE'}) { $reference_genome = $config_hash{'REFERENCE'}; }
                    else { report_missing('REFERENCE'); }
            }
            # Check for parameters on command line
            elsif ($num_args == 2)
            {
                $samtools_dir = $args[0];
                $bcftools_dir = $args[1];
            }
            else
            {
                print "ERROR: Unexpected number of parameters given ($num_args). Program will exit.\n";
                die "Try ./GBS_pipeline.pl -help for options.\n";
            }

            require "$Bin/GBS_function4.pl";
            f4($samtools_dir, $bcftools_dir, $population, $index_file, $output_dir, $reference_genome);

            summarize($start);
        }

        default
        {
            # Invoke usage information
            pod2usage(-verbose => 1, -msg => "ERROR: $FUNCTION does not exist. Try ./GBS_pipeline.pl -help for options.");
        }
    }
}
else
{
    # If no function is provided, invoke usage information
    pod2usage(-verbose => 1, -msg => "ERROR: No function specified. See ./GBS_pipeline.pl -help for options.");
}

#########################
##### PRINT SUMMARY #####
#########################
# Input: The start time

sub summarize
{
    print "Complete! ";
    my $start = $_[0];
    my $end = Time::HiRes::gettimeofday();
    printf("Time elapsed: %.2f s\n", $end - $start);
}

#########################
##### ADD TO CONFIG #####
#########################
# Input: Parameter name, value and a comment describing the parameter.

sub add_to_config
{
    my $variable_name = $_[0];
    my $value = $_[1];
    my $comment = $_[2];

    open CONFIG, ">>$config_file" or die "ERROR: Unable to open config file $config_file\n";

    # If the variable exists but has been altered, alter the file accordingly
    if ( `grep $variable_name $config_file` )
    {
        # Finds the variable name and replaces the whole line with the variable name + the new value
        # Yes, it's a perl one-liner within a perl script... but it does the trick
        # First prevent any special characters in $value from being used in the regex
        my $cmd = "perl -pi -e s{^$variable_name=.*}{$variable_name=$value}g $config_file";
        my ( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf ) =
            run( command => $cmd, verbose => 0 );
        unless ($success)
        {   print "ERROR: Unable to replace $variable_name in $CONFIG_FILE:\n$error_message\n@$stderr_buf";   }
    } else # The variable does not yet exist in the file, so append it.
    {
        print CONFIG "#$comment\n$variable_name=$value\n\n";
    }
    close CONFIG or die "ERROR: Unable to close config file $config_file\n";
}

####################################
##### REPORT MISSING PARAMETER #####
####################################
# Input: Name of parameter as it appears in the config file.

sub report_missing
{
    my $param = $_[0];
    die "ERROR: Could not find a value for required parameter \"$param\" in $config_file. Please ensure you've filled in all required fields for this step.\n";
}

###########################
##### PROGRESS REPORT #####
###########################
# Input: A current count of the number of steps completed, the total number of steps

sub print_progress
{
    my $step_count = $_[0];
    my $num_steps = $_[1];
    my $message = $_[2];

    select(STDOUT);

    # Check if a message was given, otherwise give it the empty string
    unless ( length $message ) { $message = ""; }
    # Calculate percentage of steps completed
    my $percent_complete = ($step_count/$num_steps)*100;
    my $steps;
    # Remove decimal places for simplicity
    $percent_complete = int $percent_complete;

    print " [";
    # Determine the length of the bar
    for ($steps=0; $steps<$percent_complete; $steps=$steps+4)
    {
        print "=";
    }
    # Determine the space remaining after the bar
    my $steps_remaining = (100 - $steps);
    for (my $i = 0; $i < $steps_remaining; $i = $i+4)
    {
        print " ";
    }
    # Output percentage then shift cursor to beginning of the line
    print "] $percent_complete %  $message\r";
}

###############
##### POD #####
###############

=pod

=head1 NAME

GBS_Pipeline.pl - A complete set of commands to demultiplex, trim, align and call raw variants on paired-end reads for the purpose of analyzing reads generated by genotyping by sequencing (GBS).

=head1 SYNOPSIS

./GBS_Pipeline.pl [function] [arg1] [arg2] ...

=head1 DESCRIPTION

The pipeline contains a set of steps (functions) that can be called individually to
complete a GBS analysis given multiplexed paired-end read data.

It is recommended that the GBS_pipeline files be placed in a new directory created
specifically for the GBS analysis to be performed. Running all steps of the pipeline will
create the following directories:

F<demultiplex/ trim/ align/ variants/>

where outputs from each step are placed (with the exception of summary files).

=head2 FUNCTIONS

=over 6

=item B<demultiplex> population F<index_file> re_site F<read1_file read2_file>

Demultiplex reads based on a index file.

population can be any generic name to represent this GBS run. It is only used in the
naming of output files. Avoid use of whitespace! (Ex: lens culinaris => lens_culinaris)

The index file is a simple text file and can have one of two formats. Either it is a single
column list of the indices used for this GBS run, or it consists of 2 tab-delimited columns:
- The first column contains the sample names
- The second column consists of the index that is associated with the sample name in the
  first column.
Either format provides enough information for the pipeline to demultiplex the read files,
however it is recommended to use the second format as the output files will be named using
the sample names rather than the indices, which saves a step for the user.
Note that the indices should consist of the overhang sequence that results from cleaving
of the recognition site (ie. if an index is CGAT and the restriction enzyme used is ApaL1,
then the index in the file should be CGATTGCA)

re_site is the overhang sequence (ex. TGCA in the case of ApaL1) from the rare-cutter
restriction enzyme site used in the GBS protocol (2-enzyme GBS only)

read1_file and read2_file should be provided in FASTQ format version Illumina 1.8+

output_dir is a user-specified directory for placement of processed reads. This can be
beneficial when running analysis on a machine or server where space is limited, since
very large files can be directed to a separate storage unit or location. The user can
specify "." when wanting to use the current working directory.

=item B<trim_reads> F<trimmomatic_path trim_file> [options]

Trim low quality bases and remove Illumina adaptors from raw FASTQ reads using a
command-line tool called Trimmomatic (Bolger, A. M., Lohse, M., & Usadel, B. (2014).
Trimmomatic: A flexible trimmer for Illumina Sequence Data. Bioinformatics, btu170.)

trimmomatic_path is the full pathname to the user's copy of Trimmomatic. If Trimmomatic
is not found at the trimmomatic_path, the user is prompted to install the latest version
to the current working directory.

trim_file is the filename for a list of Illumina adaptor sequences or other sequences in
FASTA format which are desired to be trimmed from the raw reads.

Keep in mind that some output from the previous step (demultiplexing reads) is also needed
as input into the trimming step. The input files are expected in the current working directory
with the following formats: sample_population_R1.fastq and sample_population_R2.fastq

The following parameters are given to trimmomatic as defaults, but may be altered in the
code manually (see file: GBS_function2.pl). Refer to the manual for trimmomatic for full
option descriptions.

Options:
    -seed_mismatches [2]
    -palindrome_clip_threshold [30]
    -simple_clip_threshold [10]
    -window_size [4]
    -required_quality [15]
    -leading [3]
    -trailing [3]
    -minlen [36]
    -version [0.32]

=item B<align_reads> F<bowtie2_dir reference_genome> [-- options]

Aligns FASTQ reads to a reference genome using a command-line tool called bowtie2 (Langmead B,
Salzberg S. Fast gapped-read alignment with Bowtie 2. Nature Methods. 2012, 9:357-359.)

bowtie2_dir is the full path of the directory with the user's copy of bowtie2, and is required.

reference_genome is the pathname of the reference genome sequence, normally in FASTA format.
bowtie2 also requires index files of the genomes, which it will use to align the reads to
the reference (and thus completely ignore the original sequence FASTA file). If index files
have not been pre-built, then the program will produce them using the reference genome
provided (they will have the same basename as the reference, with suffixes such as .1.bt2).
If index files ARE already present, ensure they are in the same directory as the reference
with the same basename as the provided reference genome file (ie. reference_genome_file.1.bt2
etc... as well as reference_genome_file.FASTA).

The user has the option to provide specific parameters to bowtie2. If no options are given,
bowtie2 is run with the following default options:
    --end-to-end:
            requires the entire read align from one end to the
            other without any more trimming, all alignment
            scores are =< 0
    --no-mixed:
            disallows bowtie2 from finding alignments for
            individual mates
    --no-discordant:
            limits bowtie2 to only make concordant alignments
    -X [11000]:
            max fragment length for valid paired-end alignment
    -R [5]:
            max number of times reads with repetitive seeds
            will be re-seeded
    -k [3]:
            search for at most k distinct, valid alignments for
            each read
    -p [4]:
            the number of parallel search threads to run

The --no-sq and --no-hd options are also supplied by default to suppress SAM header lines
for downstream processing (and therefore should not be supplied by the user as they will
be called regardless if custom parameters are given).

To provide custom options, note that the above listed options will no longer be set
as defaults, meaning that the user may need to re-specify some default options that they may wish
to keep. For example, to change -X to 1000 but keep the remaining defaults as they are, they will
have to also be given as parameters. Additional parameters can also be passed to bowtie2 in the
same format as running bowtie2 from the command line. For a full list of options, run bowtie2 --help
or refer to the manual at http://bowtie-bio.sourceforge.net/bowtie2/manual.shtml .

You MUST begin the list of custom options with a double dash '--' such that the main program will
ignore the options and pass them along to bowtie2. For example:
    ./GBS_Pipeline.pl f3 ~/BINF/Tools/bowtie2-2.2.3 \
    ../Reference_genome.fasta -- --end-to-end --no-mixed -X \
    10000 -k 2 -p 8 --very-sensitive

Finally, one parameter is unique to this function:
    --index-files [path/to/index-files/basename]
            specifies the full path and basename (no extension)
            of index files for the reference genome. This option
            is only required if they have been pre-built in
            another directory or with a different basename than
            the reference genome. Use this option BEFORE listing
            bowtie2 custom options (ie. prior to the '--')

=item B<SNP_calling> F<samtools_dir>

Bowtie2 outputs alignments in SAM file format, which is a generic format for storing sequence
alignments against a reference genome. This SAM file can be sorted, indexed, compressed, and more
using SAMtools (Li H.*, Handsaker B.*, Wysoker A., Fennell T., Ruan J., Homer N., Marth G., Abecasis G., Durbin R. and 1000 Genome Project Data Processing Subgroup (2009) The Sequence alignment/map (SAM) format and SAMtools. Bioinformatics, 25, 2078-9.)

This step will filter the alignments, convert to BAM format, sort and index them so they can be
viewed using the samtools tview command. Additionally, genotype likelihoods are calculated and
output in binary call format (bcf) and variant call format (vcf), which can be viewed with the
bcftools view command.

samtools_dir is the location of the user's copy of SAMtools (v1.0+)
bcftools_dir is the location of the user's copy of bcftools (v1.0+)

=back

=head1 SUMMARIES

=over 5

=item F<population_demultiplex_summary.txt>

 Provides an overview of demultiplexing the raw reads.

 Sample: The sample name OR the barcode used to distinguish this sample
 Read1 count: The number of R1 reads that contained the barcode
 % of Raw Read1: The % of raw R1 reads that contained the barcode
 Read2 count: The number of R2 reads that contained the barcode
 $ of Raw Read2: The % of raw R2 reads that contained the barcode

=item F<population_trim_summary.txt>

 Provides an overview of trimming the demultiplexed reads.

 Sample: The sample name OR the index used to distinguish this sample
 Input Read Pairs: The number of paired-end reads prior to trimming
 Surviving Read Pairs: The number of reads where both pairs survived
 % Both Surviving: The % of both paired reads surviving
 Only Forward Surviving: The number of forward-orientated reads that
    survived but the other pair did not
 % Forward Surviving: The % of forward-orientated reads that survived
 Only Reverse Surviving: The number of reverse-oriented reads that
    survived but the other pair did not
 % Reverse Surviving: The % of reverse-orientated reads that survived
 Dropped Reads: The number of reads dropped due to contamination or
    low quality
 % Dropped: The % of reads dropped

=item F<population_align_summary.txt>

 Provides an overview of the alignment of reads to a reference genome.

 Sample: The sample name OR the index used to distinguish this sample
 Input Reads: Number of reads when the alignment began
 Unique Reads: Number of reads that mapped uniquely to the genome
 % Unique: The % of uniquely mapping reads
 Overall Alignment Rate: The % of input reads that successfully aligned

=back

=head1 AUTHOR

Carolyn Caron - <carolyn.caron@usask.ca>

=cut
