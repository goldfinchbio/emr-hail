# VEP and LOFTEE Pre-Install

## Table of Contents

- [VEP and LOFTEE Pre-Install](#vep-and-loftee-pre-install)
  - [Table of Contents](#table-of-contents)
  - [Preqequisites](#preqequisites)
  - [VEP](#vep)
    - [S3 Setup](#s3-setup)
  - [LOFTEE](#loftee)
    - [S3 Setup](#s3-setup-1)
  - [Hail VEP Configuration JSON](#hail-vep-configuration-json)
    - [GRCh37 - LOFTEE Included](#grch37---loftee-included)
    - [GRCh38 - no LOFTEE](#grch38---no-loftee)

The VEP GRCh37 and GRCh38 indexed cache files must be downloaded and placed in your Hail S3 bucket.   These cache files change between release.
[LOFTEE](https://github.com/konradjk/loftee) files must also exist for GRCh37.

## Preqequisites

- The `hail-s3.yml` stack has been deployed in your account.  You will upload files to this bucket.

## VEP

Download the proper cache files for your release via [Ensembl's FTP site](ftp://ftp.ensembl.org/pub/).

### S3 Setup

In this example we'll download the [release 96 cache](ftp://ftp.ensembl.org/pub/release-96/variation/indexed_vep_cache/).  Note that these files will be in the 10-20 GB range.

Download via `curl`:

```bash
curl -O ftp://ftp.ensembl.org/pub/release-96/variation/indexed_vep_cache/homo_sapiens_vep_96_GRCh37.tar.gz
curl -O ftp://ftp.ensembl.org/pub/release-96/variation/indexed_vep_cache/homo_sapiens_vep_96_GRCh38.tar.gz
```

Upload to the expected path in S3 via CLI:

```bash
aws s3 mv homo_sapiens_vep_96_GRCh37.tar.gz s3://<YOUR_BUCKET_NAME>/vep/cache/
aws s3 mv homo_sapiens_vep_96_GRCh38.tar.gz s3://<YOUR_BUCKET_NAME>/vep/cache/
```

## LOFTEE

[LOFTEE](https://github.com/konradjk/loftee) is installed with VEP for use with GRCh37.   It is not yet available for GRCh38.  If you'd like to politely voice your desire for a GRCh38 version see this [GitHub Issue](https://github.com/konradjk/loftee/issues/38).

### S3 Setup

Review the [LOFTEE respository](https://github.com/konradjk/loftee) for detailed installation instructions.  For this use case, the following 3 files are expected in your Hail S3 bucket by the VEP installation scripts.

SQL database - Download locally and upload to your Hail S3 bucket.

```bash
curl -O https://personal.broadinstitute.org/konradk/loftee_data/GRCh37/phylocsf_gerp.sql.gz
aws s3 mv phylocsf_gerp.sql.gz s3://<YOUR_BUCKET_NAME>/vep/loftee_data/
```

human_ancestor_fa file - Download locally and upload to your Hail S3 bucket.

```bash
curl -O https://s3.amazonaws.com/bcbio_nextgen/human_ancestor.fa.gz
aws s3 mv human_ancestor.fa.gz s3://<YOUR_BUCKET_NAME>/vep/loftee_data/
```

GERP base file - Download locally and upload to your Hail S3 bucket.

```bash
curl -O https://personal.broadinstitute.org/konradk/loftee_data/GRCh37/GERP_scores.final.sorted.txt.gz
aws s3 mv human_ancestor.fa.gz s3://<YOUR_BUCKET_NAME>/vep/loftee_data/
```

## Hail VEP Configuration JSON

The [Hail vep method](https://hail.is/docs/0.2/methods/genetics.html#hail.methods.vep) requires a JSON configuration.  When calling the method the `config` argument can be an S3 path.

Below is a notebook example assuming `mt` is an existing [MatrixTable](https://hail.is/docs/0.2/overview/matrix_table.html).

```ipynb
mt = hl.vep(mt, "s3://<YOUR_BUCKET_NAME>/vep-configuration-GRCh37.json")
mt.describe()
```

The examples below can be stored in your Hail S3 bucket and referenced by their path - E.g. `s3://<YOUR_BUCKET_NAME>/vep-configuration-GRCh37.json`.  Configuration files can be re-used across VEP versions as they only reference GRCh version, not the VEP version.

These files are not required for building a successful AMI.  They are only used directly via Hail.

### GRCh37 - LOFTEE Included

```json
{
        "command": [
                "/opt/ensembl-vep/vep",
                "--format", "vcf",
                "--dir_plugins", "/opt/vep/plugins",
                "--dir_cache", "/opt/vep/cache",
                "--json",
                "--everything",
                "--allele_number",
                "--no_stats",
                "--cache", "--offline",
                "--minimal",
                "--assembly", "GRCh37",
                "--plugin", "LoF,human_ancestor_fa:/opt/vep/loftee_data/human_ancestor.fa.gz,filter_position:0.05,min_intron_size:15,conservation_file:/opt/vep/loftee_data/phylocsf_gerp.sql,gerp_file:/opt/vep/loftee_data/GERP_scores.final.sorted.txt.gz",
                "-o", "STDOUT"
        ],
        "env": {
                "PERL5LIB": "/opt/vep"
        },
    "vep_json_schema": "Struct{assembly_name:String,allele_string:String,ancestral:String,colocated_variants:Array[Struct{aa_allele:String,aa_maf:Float64,afr_allele:String,afr_maf:Float64,allele_string:String,amr_allele:String,amr_maf:Float64,clin_sig:Array[String],end:Int32,eas_allele:String,eas_maf:Float64,ea_allele:String,ea_maf:Float64,eur_allele:String,eur_maf:Float64,exac_adj_allele:String,exac_adj_maf:Float64,exac_allele:String,exac_afr_allele:String,exac_afr_maf:Float64,exac_amr_allele:String,exac_amr_maf:Float64,exac_eas_allele:String,exac_eas_maf:Float64,exac_fin_allele:String,exac_fin_maf:Float64,exac_maf:Float64,exac_nfe_allele:String,exac_nfe_maf:Float64,exac_oth_allele:String,exac_oth_maf:Float64,exac_sas_allele:String,exac_sas_maf:Float64,id:String,minor_allele:String,minor_allele_freq:Float64,phenotype_or_disease:Int32,pubmed:Array[Int32],sas_allele:String,sas_maf:Float64,somatic:Int32,start:Int32,strand:Int32}],context:String,end:Int32,id:String,input:String,intergenic_consequences:Array[Struct{allele_num:Int32,consequence_terms:Array[String],impact:String,minimised:Int32,variant_allele:String}],most_severe_consequence:String,motif_feature_consequences:Array[Struct{allele_num:Int32,consequence_terms:Array[String],high_inf_pos:String,impact:String,minimised:Int32,motif_feature_id:String,motif_name:String,motif_pos:Int32,motif_score_change:Float64,strand:Int32,variant_allele:String}],regulatory_feature_consequences:Array[Struct{allele_num:Int32,biotype:String,consequence_terms:Array[String],impact:String,minimised:Int32,regulatory_feature_id:String,variant_allele:String}],seq_region_name:String,start:Int32,strand:Int32,transcript_consequences:Array[Struct{allele_num:Int32,amino_acids:String,appris:String,biotype:String,canonical:Int32,ccds:String,cdna_start:Int32,cdna_end:Int32,cds_end:Int32,cds_start:Int32,codons:String,consequence_terms:Array[String],distance:Int32,domains:Array[Struct{db:String,name:String}],exon:String,gene_id:String,gene_pheno:Int32,gene_symbol:String,gene_symbol_source:String,hgnc_id:String,hgvsc:String,hgvsp:String,hgvs_offset:Int32,impact:String,intron:String,lof:String,lof_flags:String,lof_filter:String,lof_info:String,minimised:Int32,polyphen_prediction:String,polyphen_score:Float64,protein_end:Int32,protein_start:Int32,protein_id:String,sift_prediction:String,sift_score:Float64,strand:Int32,swissprot:String,transcript_id:String,trembl:String,tsl:Int32,uniparc:String,variant_allele:String}],variant_class:String}"
}
```

### GRCh38 - no LOFTEE

```json
{
    "command": [
        "/opt/ensembl-vep/vep",
        "--format", "vcf",
        "--dir_plugins", "/opt/vep/plugins",
        "--dir_cache", "/opt/vep/cache",
        "--json",
        "--everything",
        "--allele_number",
        "--no_stats",
        "--cache", "--offline",
        "--minimal",
        "--assembly", "GRCh38",
        "-o", "STDOUT"
    ],
    "env": {
        "PERL5LIB": "/opt/vep"
    },
    "vep_json_schema": "Struct{assembly_name:String,allele_string:String,ancestral:String,colocated_variants:Array[Struct{aa_allele:String,aa_maf:Float64,afr_allele:String,afr_maf:Float64,allele_string:String,amr_allele:String,amr_maf:Float64,clin_sig:Array[String],end:Int32,eas_allele:String,eas_maf:Float64,ea_allele:String,ea_maf:Float64,eur_allele:String,eur_maf:Float64,exac_adj_allele:String,exac_adj_maf:Float64,exac_allele:String,exac_afr_allele:String,exac_afr_maf:Float64,exac_amr_allele:String,exac_amr_maf:Float64,exac_eas_allele:String,exac_eas_maf:Float64,exac_fin_allele:String,exac_fin_maf:Float64,exac_maf:Float64,exac_nfe_allele:String,exac_nfe_maf:Float64,exac_oth_allele:String,exac_oth_maf:Float64,exac_sas_allele:String,exac_sas_maf:Float64,id:String,minor_allele:String,minor_allele_freq:Float64,phenotype_or_disease:Int32,pubmed:Array[Int32],sas_allele:String,sas_maf:Float64,somatic:Int32,start:Int32,strand:Int32}],context:String,end:Int32,id:String,input:String,intergenic_consequences:Array[Struct{allele_num:Int32,consequence_terms:Array[String],impact:String,minimised:Int32,variant_allele:String}],most_severe_consequence:String,motif_feature_consequences:Array[Struct{allele_num:Int32,consequence_terms:Array[String],high_inf_pos:String,impact:String,minimised:Int32,motif_feature_id:String,motif_name:String,motif_pos:Int32,motif_score_change:Float64,strand:Int32,variant_allele:String}],regulatory_feature_consequences:Array[Struct{allele_num:Int32,biotype:String,consequence_terms:Array[String],impact:String,minimised:Int32,regulatory_feature_id:String,variant_allele:String}],seq_region_name:String,start:Int32,strand:Int32,transcript_consequences:Array[Struct{allele_num:Int32,amino_acids:String,appris:String,biotype:String,canonical:Int32,ccds:String,cdna_start:Int32,cdna_end:Int32,cds_end:Int32,cds_start:Int32,codons:String,consequence_terms:Array[String],distance:Int32,domains:Array[Struct{db:String,name:String}],exon:String,gene_id:String,gene_pheno:Int32,gene_symbol:String,gene_symbol_source:String,hgnc_id:String,hgvsc:String,hgvsp:String,hgvs_offset:Int32,impact:String,intron:String,lof:String,lof_flags:String,lof_filter:String,lof_info:String,minimised:Int32,polyphen_prediction:String,polyphen_score:Float64,protein_end:Int32,protein_start:Int32,protein_id:String,sift_prediction:String,sift_score:Float64,strand:Int32,swissprot:String,transcript_id:String,trembl:String,tsl:Int32,uniparc:String,variant_allele:String}],variant_class:String}"
}
```
