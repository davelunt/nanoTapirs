#-----------------------------------------------------
# metaclese
# ---------
# A metabarcoding workflow using snakemake
# this file runs other snakemake worksflows in the rules
# directory
#-----------------------------------------------------

import os


config: "config.yaml"    #this is for when we have one --Mike

# Flag "$ snakemake" with "--report" to use
report: "reports/metacles.rst"       #this is for generating a report of the workflow
					#aswell as providing a report on the full workflow progress, individual output reports can be written to it by flagging the output with report()
						#eg. report(<real_output>)
						#Ive done this to rule fastp to demonstrate -- Mike


# get the sequence files into a list. CHECK is this a library not sample?
LIBS,=glob_wildcards("data/00_raw/{library}.R1.fastq.gz")
#LIBS=["BLEL01","testlib"]
## check libraries and LIBS are named OK throughout

SAMPLES="BLEL01"
#SAMPLES, = glob_wildcards("data/01_dmpxd/testlib/{sample}.R1.fastq.gz")

## COMMENT [Marco]:
## libs is the name of the libraries and it can be taken from the fastq.gz
## files in 00_raw folder. Sample names though might need to be specified
## in a separate file (??) or after demultiplex (??)

R=['R1', 'R2']
conda_envs=["metacles.yaml", "basta_LCA.yaml"]

#-----------------------------------------------------
# target rule, specify outputs
#-----------------------------------------------------
rule all:
    input:
        #expand("data/00_raw/{library}.{R}.fastq.gz", library=LIBS, R=R),
        #directory(expand("data/01_dmpxd/{library}/", library=LIBS, R=R)),
        expand("data/02_trimmed/{library}/{sample}.{R}.fastq.gz", library=LIBS, sample=SAMPLES, R=R),
        expand("data/03_denoised/{library}/{sample}.fasta", library=LIBS, sample=SAMPLES, R=R),
        expand("results/blast/{library}/{sample}_blast.out", library=LIBS, sample=SAMPLES),
        expand("results/LCA/{library}/{sample}.basta_LCA.out", library=LIBS, sample=SAMPLES),
        #expand("results/LCA/{library}/{sample}.basta_LCA.out.biom", library=LIBS, sample=SAMPLES),
		#expand("results/basta/{sample}.basta_LCA.out", library=LIBS, sample=SAMPLES),
        # reports ----------------------------------------------
        expand("reports/fastp/{library}/{sample}.json", library=LIBS, sample=SAMPLES),
        expand("reports/fastp/{library}/{sample}.html", library=LIBS, sample=SAMPLES),
        expand("reports/vsearch/{library}/{sample}.denoise.biom", library=LIBS, sample=SAMPLES),
        expand("reports/vsearch/{library}/{sample}_fq_eestats", library=LIBS, sample=SAMPLES),
        expand("reports/vsearch/{library}/{sample}_fq_readstats", library=LIBS, sample=SAMPLES),
        expand("reports/krona/{library}/{sample}.basta_to_krona.html", library=LIBS, sample=SAMPLES),
        expand("reports/archived_envs/{conda_envs}", conda_envs=conda_envs)

#-----------------------------------------------------
# include rule files
#-----------------------------------------------------

# include: os.path.join("rules/qc.smk"),
# include: "rules/reports.smk",
# #include: "rules/kraken.smk",
# include: "rules/blast.smk",
# include: "rules/qc.smk"

# #-----------------------------------------------------
# # gzip demultiplexed files, seqkit
# # should modify demultiplex.py to do this
# #-----------------------------------------------------
# rule gzip:
#     input:
#         "data/01_dmpxd/{library}/{sample}.{R}.fastq"
#     output:
#         "data/1_dmpxd/{library}/{sample}.{R}.fastq.gz"
#     shell:
#         "gzip {input} > {output}"

#-----------------------------------------------------
# fastp, control for sequence quality
#-----------------------------------------------------
rule fastp_trim_and_merge:
    message: "Beginning fastp QC of raw data"
    conda:
        "envs/metacles.yaml"
    input:
        read1 = "data/01_dmpxd/{library}/{sample}.R1.fastq.gz",
        read2 = "data/01_dmpxd/{library}/{sample}.R2.fastq.gz"
    output:
        out1 = "data/02_trimmed/{library}/{sample}.R1.fastq.gz",
        out2 = "data/02_trimmed/{library}/{sample}.R2.fastq.gz",
        out_unpaired1 = "data/02_trimmed/{library}/{sample}.unpaired.R1.fastq.gz",
        out_unpaired2 = "data/02_trimmed/{library}/{sample}.unpaired.R2.fastq.gz",
        out_failed = "data/02_trimmed/{library}/{sample}.failed.fastq.gz",
        merged="data/02_trimmed/{library}/{sample}.merged.fastq.gz",
        json = "reports/fastp/{library}/{sample}.json",
        html = "reports/fastp/{library}/{sample}.html"
    shell:
        "fastp \
        -i {input.read1} \
        -I {input.read2} \
        -o {output.out1} \
        -O {output.out2} \
        -j {output.json} \
        -h {output.html} \
        --qualified_quality_phred 30 \
        --length_required 90 \
        --unpaired1 {output.out_unpaired1} \
        --unpaired2 {output.out_unpaired2} \
        --failed_out {output.out_failed} \
        --cut_tail \
        --trim_front1 20 \
        --trim_front2 20 \
        --max_len1 106 \
        --max_len2 106 \
        --merge \
        --merged_out {output.merged} \
        --overlap_len_require 90 \
        --correction \
        "

#-----------------------------------------------------
# vsearch, convert files from fastq to fasta
#-----------------------------------------------------
rule fastq_to_fasta:
    conda:
        "envs/metacles.yaml"
    input:
        "data/02_trimmed/{library}/{sample}.merged.fastq.gz"
    output:
        "data/02_trimmed/{library}/{sample}.merged.fasta",
    shell:
        "vsearch \
            --fastq_filter {input} \
            --fastaout {output}"

#-----------------------------------------------------
# vsearch fastq fqreport
#-----------------------------------------------------
rule vsearch_reporting:
    conda:
        "envs/metacles.yaml"
    input:
        "data/02_trimmed/{library}/{sample}.merged.fastq.gz"
    output:
        fqreport = "reports/vsearch/{library}/{sample}_fq_eestats",
        fqreadstats = "reports/vsearch/{library}/{sample}_fq_readstats"
    shell:
        "vsearch --fastq_eestats {input} --output {output.fqreport} ; \
        vsearch --fastq_stats {input} --log {output.fqreadstats}"

#-----------------------------------------------------
# dereplication
#-----------------------------------------------------
rule vsearch_dereplication:
    conda:
        "envs/metacles.yaml"
    input:
        "data/02_trimmed/{library}/{sample}.merged.fasta"
    output:
        "data/02_trimmed/{library}/{sample}.merged.derep.fasta"
    shell:
        "vsearch --derep_fulllength {input} --sizeout --output {output}"

#-----------------------------------------------------
# denoise, remove sequence errors
#-----------------------------------------------------
rule vsearch_denoising:
    conda:
        "envs/metacles.yaml"
    input:
        "data/02_trimmed/{library}/{sample}.merged.derep.fasta"
    output:
        fasta="data/03_denoised/{library}/{sample}.fasta",
        biom="reports/vsearch/{library}/{sample}.denoise.biom"
    #params:
    #    log="reports/denoise/{library}/vsearch.log"
    shell:
        "vsearch --cluster_unoise {input} --centroids {output.fasta} --biomout {output.biom}"#" --notrunclabels" # --log {params.log}"

#-----------------------------------------------------
# chimera removal, vsearch
#-----------------------------------------------------
rule vsearch_dechimerisation: # output needs fixing
    conda:
        "envs/metacles.yaml"
    input:
        "data/03_denoised/{library}/{sample}.fasta"
    output: # fix
        text = "data/03_denoised/{library}/{sample}_chimera.txt",
        fasta = "data/03_denoised/{library}/nc_{sample}.fasta"
    shell:
        "vsearch --uchime3_denovo {input} --uchimeout {output.text} --nonchimeras {output.fasta}"

#-----------------------------------------------------
# blastn, sequence similarity search
#-----------------------------------------------------
rule blastn:
    #message: "executing blast analsyis of sequences against database {input.database}"
    conda:
        "envs/metacles.yaml"
    input:
        db = "nt", #specify in environment.yaml
        query = "data/03_denoised/{library}/nc_{sample}.fasta"
    params:
        db_dir="~/Desktop/Marco/BLAST_DB/nt-Dec18", # database directory
        descriptions="50", # return maximum of 50 hits
        outformat="'6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore'"
    output: # need to fix this by adding library name
        "results/blast/{library}/{sample}_blast.out"
    shell:
        "blastn \
            -db {params.db_dir}/{input.db} \
            -num_threads 3 \
            -outfmt {params.outformat} \
            -max_target_seqs {params.descriptions} \
            -query {input.query} \
            -out {output}"

#-----------------------------------------------------
# LCA, Last Comomon Ancestor analysis of blast using BASTA
#-----------------------------------------------------
rule basta_LCA:
    conda:
        "envs/basta_LCA.yaml"
    input:
        "results/blast/{library}/{sample}_blast.out" #fix this
        # file of blast tabular -outfmt 6 from above
    params:
        nhits="50", # -n max number of  hits to consider for classification (default=0=all)
        minhits="3", # -m must have at least 3 hits, else ignored (default=3)
        evalue="1e-20", # -e min e-value of hit (default=0.00001)
        length="90", # -l match must be at least 90bp (default=100)
        minident="95", # -i minimum identity of hit (default=80)
        maj_percent="90", # -p 90 = taxonomy shared by 9/10 hits, (default=100 = shared by all)
        dir="/media/mike/mikesdrive/" # -d directory of database files (default: $HOME/.basta/taxonomy)
    output: # check library/sample syntax
        "results/LCA/{library}/{sample}.basta_LCA.out"
    shell:
        "basta sequence {input} {output} gb \
        -p {params.maj_percent} \
        -m {params.minhits} \
        -l {params.length} \
        -i {params.minident} \
        -n {params.nhits}"
#        "./bin/basta multiple INPUT_DIRECTORY OUTPUT_FILE MAPPING_FILE_TYPE"

#-----------------------------------------------------
# BASTA to BIOM,
# BASTA output tsv converted to BIOM, uses BIOM-convert
#-----------------------------------------------------
# rule basta_BIOM:
#     conda:
#         "envs/metacles.yaml"
#     input:
#         "results/LCA/{library}/{sample}.basta_LCA.out"
#     params:
#         json="json",
#         hdf5="hdf5"
#     output:
#         "results/LCA/{library}.basta_LCA.out.biom"
#     shell:
#         "biom convert -i {input} -o {output} --table-type='OTU table' --to-{params.hdf5}"

#-----------------------------------------------------
# BIOM to tsv GRAHAM TO CHECK
#-----------------------------------------------------
# rule BIOM_tsv:
#     input:
#         "results/LCA/{sample}.basta_LCA.out.biom"
#     output:
#         "results/LCA/{sample}.basta_LCA.out.tsv"
#     shell:
#         "biom convert -i {input} -o {output} --table-type='OTU table' --to-{params.hdf5}"

# biom convert -i table.txt -o table.from_txt_json.biom --table-type="OTU table" --to-json
# biom convert -i table.txt -o table.from_txt_hdf5.biom --table-type="OTU table" --to-hdf5
# OUTPUT: workflow should export data for downstream analysis. This is BIOM format written by metaBEAT, and also csv I guess.

#-----------------------------------------------------
# Krona
#-----------------------------------------------------
# basta2krona.py
# This creates a krona plot (html file) that can be opened in your browser from a basta annotation output file(s). Multiple files can be given separated by comma.

rule krona_LCA_plot:
    conda:
        "envs/metacles.yaml"
    input:
        "results/LCA/{library}/{sample}.basta_LCA.out"
    output:
        "reports/krona/{library}/{sample}.basta_to_krona.html"
    shell:
        "python /home/mike/anaconda3/pkgs/basta-1.3-py27_1/bin/basta2krona.py {input} {output}"

        ## DO NOT LOSE THIS COMMAND!!!!
        ## python /home/mike/anaconda3/pkgs/basta-1.3-py27_1/bin/basta2krona.py Desktop/metacles/results/LCA/testlib/BLEL01.basta_LCA.out Desktop/kronatest.html


#-----------------------------------------------------
# Archive conda environment
#-----------------------------------------------------


rule conda_env:
    conda:
        "envs/{conda_envs}"
    output:
        "reports/archived_envs/{conda_envs}"
    shell:
        "conda env export --file {output}"



# rule kraken2:
#     input:
#         query= "data/kraken/query/R2.fasta",
#         database= directory("data/kraken/db/NCBI_nt")
#     output:
#         "results/kraken/R2out.txt"
# 	# params:		## It isnt liking the use of params here for some reason. not sure why
# 	# 	database= directory("data/kraken/db/NCBI_nt")
#     shell:
#       "kraken2 --db {input.database} {input.query} --use-names --report {output}"
#
#-----------------------------------------------------
# krona
#-----------------------------------------------------
# now in the conda environment
# need to run .pl and .sh scripts to install taxonomy databases
#-----------------------------------------------------
# vegan
#-----------------------------------------------------

#-----------------------------------------------------
# seqkit, write simple report on fasta files
#-----------------------------------------------------
#rule seqkitstats:
#        input:
#            "data/05_seqkit/{library}/{sample}/extendedFrags.fas"
#        output:
#            "reports/seqkit/{library}/{sample}.seqkit_fastastats.md"
#            #"reports/seqkit/seqkit_fastastats.md"
#        shell:
#            "seqkit stats {input} | csvtk csv2md -t -o {output}"
#
