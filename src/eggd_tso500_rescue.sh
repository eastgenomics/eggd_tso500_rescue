#!/bin/bash
# eggd_tso500_rescue 1.0.0

set -exo pipefail

main() {

    echo "Value of gvcf: '$gvcf'"
    echo "Value of hotspot_vcf: '$hotspot_vcf'"

    # Download input files
    dx download "$gvcf"
    dx download "$hotspot_vcf"
    dx download "$fasta_tar"

    #Unpack fasta tar
    tar xzf $fasta_tar_name

    # Get sample prefix
    sample_prefix=${gvcf_name/_MergedSmallVariants.genome.vcf/}

    # Remove reference calls from gvcf
    bcftools view -m2 $gvcf_name -o ${sample_prefix}.vcf

    # Remove chr prefix from patient vcf to match the reference genome
    awk '{gsub(/chr/,""); print}' ${sample_prefix}.vcf > ${sample_prefix}_noChr.vcf

    # Normalise and left align filtered vcf and hotspots vcf
    bcftools norm -m -any -f genome.fa ${sample_prefix}_noChr.vcf -o ${sample_prefix}_norm.vcf
    bcftools norm -m -any -f genome.fa ${hotspot_vcf_name} -o ${hotspot_vcf_prefix}_norm.vcf.gz -O z

    # Create a vcf of all NON-PASS variants
    bcftools filter -i 'FILTER!="PASS"' ${sample_prefix}_norm.vcf  -o ${sample_prefix}_lowSupport.vcf.gz -O z

    # Create a vcf with only PASS variants
    bcftools view -f .,PASS ${sample_prefix}_norm.vcf  -o  ${sample_prefix}_pass.vcf.gz -O z

    # Zip and index vcf files to use with bcftools isec command
    bcftools index ${sample_prefix}_lowSupport.vcf.gz
    bcftools index ${sample_prefix}_pass.vcf.gz
    bcftools index ${hotspot_vcf_prefix}_norm.vcf.gz

    # Intersect non-pass vcf with hotspot list and keep sample vcf entries
    bcftools isec ${sample_prefix}_lowSupport.vcf.gz ${hotspot_vcf_prefix}_norm.vcf.gz -n =2 -w 1 \
    -o ${sample_prefix}_filtered_hotspots.vcf.gz -O z

    # Add OPA flag to everything in that vcf
    bcftools filter -e 'FORMAT/DP>0' -s OPA -m + ${sample_prefix}_filtered_hotspots.vcf.gz \
    -o ${sample_prefix}_OPAvariants.vcf.gz -O z

    bcftools index ${sample_prefix}_OPAvariants.vcf.gz

    # Concatenate OPA flagged non-pass variant vcf with pass vcf
    bcftools concat -a  ${sample_prefix}_pass.vcf.gz ${sample_prefix}_OPAvariants.vcf.gz \
    -o ${sample_prefix}_withLowSupportHotspots.vcf.gz -O z

    # Upload output vcf
    filtered_vcf=$(dx upload ${sample_prefix}_withLowSupportHotspots.vcf --brief)
    dx-jobutil-add-output filtered_vcf "$filtered_vcf" --class=file
}
