#!/usr/bin/perl -w

##### GBS_Pipeline.pl - a multi-step pipeline for GBS analysis #####
##### Usage: ./GBS_Pipeline.pl [function] [arg1] [arg2] ...
##### Functions:
#####   function1 sample_name barcode_file re_site read1_file read2_file output_dir
#####   function2 trimmomatic_path trim_file
#####   function3 bowtie2_dir reference_genome [-- options]
#####   function4 samtools_dir
##### Requirements:
#####   Trimmomatic (v0.17-0.33), Bowtie2 (v2.x.x), SAMtools (v1.x), BCFtools (v1.x)
#####   A file listing barcodes (indices) for demultiplexing
#####   Paired read data in separate FASTQ files (R1 reads and R2 reads)
#####   A file containing adaptor and other sequences for trimming purposes
#####   A FASTA file containing the reference genome
##### See the perldoc for a full description: perldoc GBS_Pipeline.pl
#####   or refer to: github.com/carolyncaron/GBSpipeline/wiki/Using-GBSpipeline-for-the-first-time
#####   for a tutorial.

=pod

=head1 NAME

GBS_Pipeline.pl - A complete set of commands to demultiplex, trim, align and call raw variants on paired-end reads for the purpose of analyzing reads generated by genotyping by sequencing (GBS).

=head1 SYNOPSIS

./GBS_Pipeline.pl [function] [arg1] [arg2] ...

=head1 DESCRIPTION

The pipeline contains a set of steps (functions) that can be called individually to
complete a GBS analysis given multiplexed paired-end read data.

It is recommended that the GBS_Pipeline files be placed in a new directory created
specifically for the GBS analysis to be performed. Running all steps of the pipeline will
create the following directories:

F<demultiplex/ trim/ align/ variants/>

where outputs from each step are placed (with the exception of summary files).

=head2 FUNCTIONS

=over 6

=item B<demultiplex> sample_name F<barcode_file> re_site F<read1_file read2_file>

Demultiplex reads based on a barcode file (provided by Illumina to distinguish samples
used in sequencing).

sample_name can be any name assigned to the reads, to be used in naming output files.
Avoid use of whitespace (Ex: lens culinaris => lens_culinaris)

re_site is the rare-cutter restriction enzyme site used in the GBS protocol

read1_file and read2_file should be provided in FASTQ format version Illumina 1.8+

output_dir is a user-specified directory for placement of processed reads. This can be
beneficial when running analysis on a machine or server where space is limited, since
very large files can be directed to a separate storage unit or location. The user can
specify . when wanting to use the current working directory.

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
with the following formats: index_samplename_R1-clip.fastq and index_samplename_R2.fastq

The following parameters are given to trimmomatic as defaults, but may be altered as command-
line options. Refer to the manual for trimmomatic for full option descriptions.

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

samtools_dir is the location of the user's version of SAMtools and should contain both samtools
and bcftools.

=back

=head1 SUMMARIES

=over 5

=item F<samplename_demultiplex_summary.txt>

 Provides an overview of demultiplexing raw reads.

 Barcode: The barcode associated with this set of reads
 Read1 count: The number of R1 reads that contained the barcode
 % of Raw Read1: The % of raw R1 reads that contained the barcode
 Read2 count: The number of R2 reads that contained the barcode
 $ of Raw Read2: The % of raw R2 reads that contained the barcode

=item F<samplename_trim_summary.txt>

 Provides an overview of trimming demultiplexed reads.

 Index: The index used to identify a sample's set of reads
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

=item F<samplename_align_summary.txt>

 Provides an overview of the alignment of reads to a reference genome.

 Index: The index used to identify a sample's set of reads
 Input Reads: Number of reads when the alignment began
 Reads Paired: Number of reads that were aligned along with their
    paired read
 % Reads Paired: The % of reads that aligned along with their paired
    read
 Overall Alignment Rate: The % of input reads that successfully aligned

=back

=head1 AUTHOR

Carolyn Caron - <carolyn.caron@usask.ca>

=cut

use strict;
use warnings;
use File::Basename;
use IO::File;
use feature qw/switch/;
use Time::HiRes;
use FindBin qw($Bin);
use IPC::Cmd qw[run];
use Pod::Usage;

#######################
##### CONFIG FILE #####
#######################
my $CONFIG_FILE = "$Bin/GBS.conf";

sub add_to_config
{
    my $variable_name = $_[0];
    my $value = $_[1];
    my $comment = $_[2];

    open CONFIG, ">>$CONFIG_FILE" or die "ERROR: Unable to open config file $CONFIG_FILE\n";

    # If the variable exists but has been altered, alter the file accordingly
    if ( `grep $variable_name $CONFIG_FILE` )
    {
        # Finds the variable name and replaces the whole line with the variable name + the new value
        # Yes, it's a perl one-liner within a perl script... but it does the trick
        # First prevent any special characters in $value from being used in the regex
        my $cmd = "perl -pi -e s{^$variable_name=.*}{$variable_name=$value}g $CONFIG_FILE";
        my ( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf ) =
            run( command => $cmd, verbose => 0 );
        unless ($success)
        {   print "ERROR: Unable to replace $variable_name in $CONFIG_FILE:\n$error_message\n@$stderr_buf";   }
    } else # The variable does not yet exist in the file, so append it.
    {
        print CONFIG "#$comment\n$variable_name=$value\n\n";
    }
    close CONFIG or die "ERROR: Unable to close config file $CONFIG_FILE\n";
}

################
##### MAIN #####
################

# Check for user-specified functions to run- if none specified, display POD #

########### TODO ##########
# Check if command line flags were provided: this overrides any non-flag options
use Getopt::Long;
#
# my ( $SAMPLE_NAME, $R1, $R2, $TRIM_DIR );
# GetOptions ('s|sample=s' => \$SAMPLE_NAME,
#             'r1=s' => \$R1, 'r2=s' => \$R2,
#             't|trimdir=s' => \$TRIM_DIR
#             );

#Options for function2/trimming
my ($seed_mismatches, $palindrome_clip_threshold, $simple_clip_threshold, $window_size,
    $required_quality, $leading, $trailing, $minlen);

GetOptions (
            'seed_mismatches=i'           => \$seed_mismatches,
            'palindrome_clip_threshold=i' => \$palindrome_clip_threshold,
            'simple_clip_threshold=i'     => \$simple_clip_threshold,
            'window_size=i'               => \$window_size,
            'required_quality=i'          => \$required_quality,
            'leading=i'                   => \$leading,
            'trailing=i'                  => \$trailing,
            'minlen=i'                    => \$minlen
            );


###########################

# Check that at least one argument is given
if ( exists ( $ARGV[0] ) )
{
    my $FUNCTION = $ARGV[0];
    shift @ARGV;
    my @args = @ARGV;
    my $num_args = $#args + 1;

    #print "User specified function $FUNCTION with $num_args args: @args\n";

    # Use a switch statement for accessing functions
    given($FUNCTION)
    {
        when ( /function1/ || /f1/ || /demultiplex/ )
        {
            unless ($num_args == 6)
            {
                print "ERROR: Unexpected number of parameters given ($num_args). Program will exit.\n";
                die "--Try: Perl GBS_pipeline.pl $FUNCTION sample_name index_file re_site ",
                    "/path/to/file1/filename1.fastq /path/to/file2/filename2.fastq /path/to/reads/\n";
            }

            my $sample = $args[0];
            my $index_file = $args[1];
            my $RE_site = $args[2];
            my $R1_file = $args[3];
            my $R2_file = $args[4];
            my $output_dir = $args[5];

            #my $start = Time::HiRes::gettimeofday();

            print "Calling $FUNCTION ...\n";

            require "$Bin/GBS_function1.pl";
            function1($sample, $index_file, $RE_site, $R1_file, $R2_file, $output_dir);
            print "Completed $FUNCTION.\n";

            # Save the sample and index file into the configuration file
            add_to_config("SAMPLE", $sample, "The generic sample name used in naming files during processing");
            add_to_config("INDEX_FILE", $index_file, "The filename of the list of indices (aka barcodes)");
            add_to_config("READS_DIR", $output_dir, "The location where output of processed reads are placed");

            #summarize($FUNCTION, $start);
        }
        when ( /function2/ || /f2/ || /trim_reads/ )
        {
            unless ($num_args == 2)
            {
                print "ERROR: Unexpected number of parameters given ($num_args). Program will exit.\n";
                die "--Try: ./GBS_pipeline.pl $FUNCTION /path/to/trimmomatic path/to/trim_file.fasta\n";
            }

            my $trimmomatic_path = $args[0];
            my $trim_file = $args[1];

            # Extract sample name, indices and output directory from the config file
            chomp(my $sample = `grep 'SAMPLE' $CONFIG_FILE | cut -d'=' -f2`);
            chomp(my $index_file = `grep 'INDEX_FILE' $CONFIG_FILE | cut -d'=' -f2`);
            chomp(my $output_dir = `grep 'READS_DIR' $CONFIG_FILE | cut -d'=' -f2`);

            ######## TODO #########
            # Save any options provided into an array

            print "Calling $FUNCTION ...\n";
            require "$Bin/GBS_function2.pl";
            f2($trimmomatic_path, $trim_file, $sample, $index_file, $output_dir);
            print "Completed $FUNCTION.\n";
        }
        when ( /function3/ || /f3/ || /align_reads/ )
        {
            unless ($num_args >= 2)
            {
                print "ERROR: Unexpected number of parameters given ($num_args). Program will exit.\n";
                die "--Try: ./GBS_pipeline.pl $FUNCTION /path/to/bowtie2_dir/ path/to/reference_genome.FASTA\n";
            }

            my $bowtie2_dir = $args[0];
            my $reference_genome = $args[1];

            # Shift @args array twice to remove first 2 required parameters
            shift @args; shift @args;

            # Extract sample name and indices from the config file
            chomp(my $sample = `grep 'SAMPLE' $CONFIG_FILE | cut -d'=' -f2`);
            chomp(my $index_file = `grep 'INDEX_FILE' $CONFIG_FILE | cut -d'=' -f2`);
            chomp(my $output_dir = `grep 'READS_DIR' $CONFIG_FILE | cut -d'=' -f2`);

            print "Calling $FUNCTION ...\n";
            require "$Bin/GBS_function3.pl";

            # Give the subroutine the remaining args (for bowtie2) as an array reference
            f3($bowtie2_dir, $reference_genome, $sample, $index_file, $output_dir, \@args);
            print "Completed $FUNCTION.\n";

            add_to_config("REFERENCE",$reference_genome,"The pathname of the reference genome sequence.");
        }
        when ( /function4/ || /f4/ || /SNP_calling/ )
        {
            unless ($num_args == 2)
            {
                print "ERROR: Unexpected number of parameters given ($num_args). Program will exit.\n";
                die "--Try: ./GBS_pipeline.pl $FUNCTION /path/to/SAMtools_dir/ /path/to/bcftools_dir/\n";
            }

            my $samtools_dir = $args[0];
            my $bcftools_dir = $args[1];

            # Extract sample name/indices/reference genome from the config file
            chomp(my $sample = `grep 'SAMPLE' $CONFIG_FILE | cut -d'=' -f2`);
            chomp(my $index_file = `grep 'INDEX_FILE' $CONFIG_FILE | cut -d'=' -f2`);
            chomp(my $output_dir = `grep 'READS_DIR' $CONFIG_FILE | cut -d'=' -f2`);
            chomp(my $reference_genome = `grep 'REFERENCE' $CONFIG_FILE | cut -d'=' -f2`);

            print "Calling $FUNCTION ...\n";
            require "$Bin/GBS_function4.pl";
            f4($samtools_dir, $bcftools_dir, $sample, $index_file, $output_dir, $reference_genome);
            print "Completed $FUNCTION.\n";
        }
        default
        {
            # Invoke the POD with a verboseness of 2 so the entire manual is printed.
            pod2usage(-verbose => 2, -msg => "ERROR: $FUNCTION does not exist.");
        }
    }
}
else ######## TODO ########
{
    # Looks at the GBS pipeline directory for files/directories present and estimates at
    # what stage in the pipeline it left off



    # If no expected files present, print the entire POD
    pod2usage(-verbose => 2, -msg => "No parameters given. See: perldoc GBS_Pipeline.pl");
}

#########################
##### PRINT SUMMARY #####
#########################

sub summarize
{
    my $function = $_[0];
    print "Completed $function.\n";
    my $start = $_[1];
    my $end = Time::HiRes::gettimeofday();
    printf("Time elapsed: %.2f s\n", $end - $start);
    print "The following files were created:\n";

    print "Continue onto the next step? (Yes/No)\n",
        "Hint: You can read your summary file then call the function for the next step,\n",
        "by typing: Perl ./GBS_pipeline.pl $function [arg1] [arg2] ... \n";
}

##################################
##### Progress reporting #########
##################################
# Input: A current count of the number of indices processed, the total number of indices
sub print_progress
{
    my $index_count = $_[0];
    my $num_indices = $_[1];
    my $message = $_[2];

    # Check if a message was given, otherwise give it the empty string
    unless ( length $message ) { $message = ""; }
    # Calculate percentage of reads indexed
    my $percent_complete = ($index_count/$num_indices)*100;
    my $steps;
    # Remove decimal places for simplicity
    $percent_complete = int $percent_complete;

    print " [";
    # Determine the length of the bar
    for ($steps=0; $steps<$percent_complete; $steps=$steps+5)
    {
        print "=";
    }
    # Determine the space remaining after the bar
    my $steps_remaining = (100 - $steps);
    for (my $i = 0; $i < $steps_remaining; $i = $i+5)
    {
        print " ";
    }
    # Output percentage then shift cursor to beginning of the line
    print "] $percent_complete %  $message\r";
}