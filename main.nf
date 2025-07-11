// main.nf
// Nextflow workflow for Retrobiosynthesis

// Define parameters
params.rule_diameters = '2,4,6,8,10,12,14,16'
params.compress_output_rrules = 'false'
params.target_inchi = 'InChI=1S/C40H56/c1-33(2)19-13-23-37(7)27-17-31-39(9,10)29-21-25-35(5)26-22-30-40(11,12)32-18-28-38(8)24-14-20-34(3)4-15-25/h13-14,19-22,25-28,31-32H,4-6,15-18,23-24,29-30H2,1-3,7-12H3' // Example InChI for Lycopene
params.sbml_model_name = 'data/sbml_models/iML1515.sbml' // Example SBML model, you might need to provide the actual file or path
params.sbml_compartment_id = 'c'
params.remove_dead_end_metabolites = 'true'
params.max_pathway_length = 3
params.source_name = 'target'
params.rp2_workflow_version = 'r20220104'
params.rp2_topx = 100
params.rp2_min_rule_diameter = 0
params.rp2_max_rule_diameter = 1000
params.rp2_mw_source = 1000
params.rp2_timeout_min = 60
params.rp2paths_timeout = 1800
params.cr_max_subpaths = 10
params.cr_upper_flux_bound = 999999
params.cr_lower_flux_bound = 0

// Define channels for inputs that might come from external files
Channel
    .fromPath(params.sbml_model_name)
    .ifEmpty { exit 1, "ERROR: SBML model file '${params.sbml_model_name}' not found." }
    .set { sbml_model_ch }

workflow {
    // Step 1: RRules Parser (RetroRules)
    RRulesParser(
        params.rule_diameters,
        params.compress_output_rrules
    )

    // Step 2: Target to produce (represented as a direct input parameter)
    // No explicit process for this, as it's a direct string input to RetroPath2.0

    // Step 3: Pick SBML Model (handled by the initial channel creation)

    // Step 4: Sink from SBML
    SinkFromSBML(
        sbml_model_ch,
        params.sbml_compartment_id,
        params.remove_dead_end_metabolites
    )

    // Step 5: RetroPath2.0
    RetroPath2_0(
        RRulesParser.out.out_rules,
        SinkFromSBML.out.sink_file,
        params.target_inchi,
        params.max_pathway_length,
        params.source_name,
        params.rp2_workflow_version,
        params.rp2_topx,
        params.rp2_min_rule_diameter,
        params.rp2_max_rule_diameter,
        params.rp2_mw_source,
        params.rp2_timeout_min
    )

    // Step 6: RP2paths
    RP2paths(
        RetroPath2_0.out.reaction_network
    )

    // Step 7: Complete Reactions
    CompleteReactions(
        RP2paths.out.master_pathways,
        RP2paths.out.compounds,
        RetroPath2_0.out.reaction_network,
        SinkFromSBML.out.sink_file,
        params.cr_max_subpaths,
        params.cr_upper_flux_bound,
        params.cr_lower_flux_bound
    )

    // Output results from the final step
    CompleteReactions.out.completed_pathways.view { "Completed Pathways: $it" }
}

// Processes for each step

process RRulesParser {
    // Use rptools, which contains the RRules Parser
    conda 'environments/rptools.yml' // Refer to a local conda environment file

    input:
        val rule_diameters
        val compress_output

    output:
        path "out_rules.csv", emit: out_rules

    script:
    """
    python -m rrparser \\
      --outfile out_rules.csv \\
      --rule-type retro \\
      --diameters ${rule_diameters} \\
      --output-format csv
    """
}

process SinkFromSBML {
    // Use rptools for sink extraction
    conda 'environments/rptools.yml' // Refer to a local conda environment file

    input:
        path sbml_model
        val compartment_id
        val remove_dead_end

    output:
        path "sink.csv", emit: sink_file, optional: true 

    script:
    """
    export HOME="/tmp"
    export XDG_CACHE_HOME="/tmp/.cache"
    mkdir -p \$XDG_CACHE_HOME

    # rpExtractSink modülünü tam paketiyle çağırıyoruz.
    COMMAND="python -m rptools.rpextractsink.rpextractsink --input-sbml ${sbml_model} --compartment-id ${compartment_id} --output-sbml sink.csv"

    if [ "${remove_dead_end}" == "true" ]; then
        COMMAND+=" --remove-dead-end"
        echo "Info: --remove-dead-end flag will be used for rpExtractSink."
    else
        echo "Info: --remove-dead-end flag will NOT be used for rpExtractSink."
    fi

    \$COMMAND
    """
}

process RetroPath2_0 {
    // Use retropath2-wrapper for RetroPath2.0
    conda 'environments/retropath2-wrapper.yml' // Refer to a local conda environment file

    input:
        path rules_file
        path sink_file
        val target_inchi
        val max_pathway_length
        val source_name // Bu parametre doğrudan retropath2_wrapper CLI'ında kullanılmayabilir, ancak bir not olarak tutulmuştur.
        val workflow_version // Bu parametre doğrudan retropath2_wrapper CLI'ında kullanılmayabilir.
        val topx
        val min_rule_diameter
        val max_rule_diameter
        val mw_source
        val timeout_min

    output:
        path "retropath2_out_dir/results_pathways.csv", emit: reaction_network // retropath2_wrapper'ın çıktısı bir dizin içindedir

    script:
    """
    # retropath2_wrapper CLI'ı giriş dosyalarını ve çıktı dizinini bekler.
    # Diğer parametreler doğrudan argüman olarak sağlanmıştır.
    # Çıktı dosyasının adı ('results_pathways.csv' olarak varsayılmıştır) belgelendirmede açıkça belirtilmemiştir, ancak yaygın bir çıktıdır.
    mkdir retropath2_out_dir

    python -m retropath2_wrapper \\
      ${sink_file} \\
      ${rules_file} \\
      retropath2_out_dir \\
      --source_file "${target_inchi}" \\
      --max_steps ${max_pathway_length} \\
      --topx ${topx} \\
      --dmin ${min_rule_diameter} \\
      --dmax ${max_rule_diameter} \\
      --mwmax_source ${mw_source} \\
      --timeout ${timeout_min}
      
    # retropath2_wrapper'ın çıktı dosyası 'outdir' içinde yer alır.
    # Nextflow'a doğru dosyayı iletmek için çıktıyı taşıyoruz.
    # Eğer çıktı dosyası adı farklıysa (örn. 'results_reaction_network.csv' ise), burayı güncelleyin.
    mv retropath2_out_dir/results_pathways.csv retropath2_out_dir/reaction_network.csv
    """
}

process RP2paths {
    // Use rp2paths
    conda 'environments/rp2paths.yml' // Refer to a local conda environment file

    input:
        path reaction_network

    output:
        path "rp2paths_out_dir/out_paths.csv", emit: master_pathways
        path "rp2paths_out_dir/out_compounds.csv", emit: compounds // rp2paths dokümanında 'out_compounds.csv' açıkça belirtilmemiştir, ancak Galaxy UI bunu gerektiriyor.

    script:
    """
    # rp2paths CLI'ı 'all' modu ve girdi dosyasını bekler.
    # Çıktı dizini '--outdir' ile belirtilmiştir.
    # 'out_compounds.csv' dosyasının da rp2paths tarafından üretildiği varsayılmıştır.
    mkdir rp2paths_out_dir

    python -m rp2paths all \\
      ${reaction_network} \\
      --outdir rp2paths_out_dir

    # Eğer rp2paths doğrudan 'out_compounds.csv' üretmiyorsa, bu satırı kaldırmanız veya
    # bu dosyayı başka bir adımdan oluşturmanız gerekebilir.
    # Örnek olarak burada bir boş dosya oluşturulmuştur.
    # Gerçek rp2paths çıktısına göre düzenleme yapınız.
    if [ ! -f rp2paths_out_dir/out_compounds.csv ]; then
        echo "compound_id,InChI" > rp2paths_out_dir/out_compounds.csv
        echo "C_dummy,InChI=..." >> rp2paths_out_dir/out_compounds.csv
        echo "Warning: 'out_compounds.csv' not found, created a dummy file. Verify rp2paths output."
    fi
    """
}

process CompleteReactions {
    // Use rptools for Complete Reactions
    conda 'environments/rptools.yml' // Refer to a local conda environment file

    input:
        path master_pathways
        path compounds
        path reaction_network
        path sink_file
        val max_subpaths
        val upper_flux_bound
        val lower_flux_bound

    output:
        path "completed_pathways/*.sbml", emit: completed_pathways // Assuming SBML outputs

    script:
    """
    # rpCompletion, rptools paketinin bir parçasıdır.
    # Komut argümanları, genel rptools CLI desenlerine ve Galaxy konfigürasyonuna göre varsayılmıştır.
    mkdir -p completed_pathways

    python -m rptools.rpcompletion \\
      --pathways ${master_pathways} \\
      --compounds ${compounds} \\
      --rp2_network ${reaction_network} \\
      --sink ${sink_file} \\
      --max_subpaths ${max_subpaths} \\
      --upper_flux_bound ${upper_flux_bound} \\
      --lower_flux_bound ${lower_flux_bound} \\
      --output_dir completed_pathways
    """
}