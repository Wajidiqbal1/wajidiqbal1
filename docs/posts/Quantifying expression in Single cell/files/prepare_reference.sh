#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

#########################################################
# Set up metadata and directories
#########################################################

# Define the genome version and build version
genome="GRCh38"
version="2020-A"

# Create a build directory to store intermediate and final files
build="GRCh38-2020-A_build"
mkdir -p "$build"

# Create a source directory to store downloaded files
source="reference_sources"
mkdir -p "$source"

#########################################################
# Download the genome (FASTA) and annotation (GTF) files
#########################################################

# URLs to download the genome and annotation files
fasta_url="http://ftp.ensembl.org/pub/release-98/fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz"
gtf_url="http://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_32/gencode.v32.primary_assembly.annotation.gtf.gz"

# Define the paths to store the downloaded files
fasta_in="${source}/Homo_sapiens.GRCh38.dna.primary_assembly.fa"
gtf_in="${source}/gencode.v32.primary_assembly.annotation.gtf"

# Download and decompress the FASTA file if it does not exist locally
if [ ! -f "$fasta_in" ]; then
    echo "Downloading and decompressing the FASTA file..."
    curl -sS "$fasta_url" | zcat > "$fasta_in"
fi

# Download and decompress the GTF file if it does not exist locally
if [ ! -f "$gtf_in" ]; then
    echo "Downloading and decompressing the GTF file..."
    curl -sS "$gtf_url" | zcat > "$gtf_in"
fi

#########################################################
# Modify sequence headers in the FASTA file
#########################################################

# Define the path for the modified FASTA file
fasta_modified="$build/$(basename "$fasta_in").modified"

# Modify the sequence headers:
# - Retain the original contig names
# - Add 'chr' prefix to autosomes and sex chromosomes
# - Rename mitochondrial chromosome to 'chrM'
echo "Modifying sequence headers in the FASTA file..."
cat "$fasta_in" \
    | sed -E 's/^>(\S+).*/>\1 \1/' \
    | sed -E 's/^>([0-9]+|[XY]) />chr\1 /' \
    | sed -E 's/^>MT />chrM /' \
    > "$fasta_modified"

#########################################################
# Modify transcript, gene, and exon IDs in the GTF file
#########################################################

# Define the path for the modified GTF file
gtf_modified="$build/$(basename "$gtf_in").modified"

# Regex pattern to match Ensembl gene, transcript, and exon IDs
ID="(ENS(MUS)?[GTE][0-9]+)\.([0-9]+)"

# Modify the IDs:
# - Strip version suffixes from gene, transcript, and exon IDs
# - Maintain version information in separate fields
echo "Modifying transcript, gene, and exon IDs in the GTF file..."
cat "$gtf_in" \
    | sed -E 's/gene_id "'"$ID"'";/gene_id "\1"; gene_version "\3";/' \
    | sed -E 's/transcript_id "'"$ID"'";/transcript_id "\1"; transcript_version "\3";/' \
    | sed -E 's/exon_id "'"$ID"'";/exon_id "\1"; exon_version "\3";/' \
    > "$gtf_modified"

#########################################################
# Define and filter transcripts based on biotype
#########################################################

# Define patterns for allowable gene and transcript types
BIOTYPE_PATTERN="(protein_coding|lncRNA|IG_C_gene|IG_D_gene|IG_J_gene|IG_LV_gene|IG_V_gene|IG_V_pseudogene|IG_J_pseudogene|IG_C_pseudogene|TR_C_gene|TR_D_gene|TR_J_gene|TR_V_gene|TR_V_pseudogene|TR_J_pseudogene)"
GENE_PATTERN="gene_type \"${BIOTYPE_PATTERN}\""
TX_PATTERN="transcript_type \"${BIOTYPE_PATTERN}\""
READTHROUGH_PATTERN="tag \"readthrough_transcript\""
PAR_PATTERN="tag \"PAR\""

# Create a gene allowlist by filtering transcripts:
# - Match allowable gene_type (biotype)
# - Match allowable transcript_type (biotype)
# - Exclude "PAR" and "readthrough_transcript" tags
echo "Creating a gene allowlist by filtering transcripts based on biotype..."
cat "$gtf_modified" \
    | awk '$3 == "transcript"' \
    | grep -E "$GENE_PATTERN" \
    | grep -E "$TX_PATTERN" \
    | grep -Ev "$READTHROUGH_PATTERN" \
    | grep -Ev "$PAR_PATTERN" \
    | sed -E 's/.*(gene_id "[^"]+").*/\1/' \
    | sort \
    | uniq \
    > "${build}/gene_allowlist"

#########################################################
# Filter the GTF file based on the gene allowlist
#########################################################

# Define the path for the filtered GTF file
gtf_filtered="${build}/$(basename "$gtf_in").filtered"

# Copy header lines (starting with '#') from the modified GTF file
echo "Filtering the GTF file based on the gene allowlist..."
grep -E "^#" "$gtf_modified" > "$gtf_filtered"

# Include only genes from the allowlist in the filtered GTF file
grep -Ff "${build}/gene_allowlist" "$gtf_modified" >> "$gtf_filtered"

#########################################################
# Create the reference package using Cell Ranger
#########################################################

# Use Cell Ranger's mkref command to create the reference package
# - Provide the modified FASTA and filtered GTF files
echo "Creating the reference package using Cell Ranger..."
cellranger mkref --ref-version="$version" \
    --genome="$genome" --fasta="$fasta_modified" --genes="$gtf_filtered"

echo "Reference package creation complete."
