
    # Functions and methods for cheme::Cascade.HollowIonScheme computations


    """
    `Cascade.computeSteps(scheme::Cascade.HollowIonScheme, comp::Cascade.Computation, stepList::Array{Cascade.Step,1})` 
        ... computes in turn all the requested (decay) transition amplitudes as well as AutoIonization.Line's, etc. for all 
            pre-specified decay steps of the cascade. When compared with standard computations of these atomic 
            processes, however, the amount of output is largely reduced and often just printed into the summary file. 
            A set of  data::Cascade.DrRateData  is returned.
    """
    function computeSteps(scheme::Cascade.HollowIonScheme, comp::Cascade.Computation, stepList::Array{Cascade.Step,1})
        linesA = AutoIonization.Line[];    linesR = PhotoEmission.Line[];    linesC = ElectronCapture.Line[];    cOrbitals = Dict{Subshell, Orbital}()
        printSummary, iostream = Defaults.getDefaults("summary flag/stream")
        nt = 0;   st = 0;   previousMeanEn = 0.
        for  step  in  stepList
            st = st + 1
            nc = length(step.initialMultiplet.levels) * length(step.finalMultiplet.levels)
            sa = "\n  $st) Perform $(string(step.process)) amplitude computations for up to $nc decay lines (without selection rules): "
            println(sa);    if  printSummary   println(iostream, sa)   end 
                                                 
            if      step.process == Basics.ElecCapture() 
                # Compute continuum orbitals independently for all transitions in the given block.
                newLines = DielectronicCapture.computeLinesCascade(step.finalMultiplet, step.initialMultiplet, comp.nuclearModel, comp.grid, 
                                                               step.settings, output=true, printout=false) 
                append!(linesC, newLines);    nt = length(linesC)
            elseif  step.process == Basics.Auger() 
                # Compute continuum orbitals independently for all transitions in the given block.
                newLines = AutoIonization.computeLinesCascade(step.finalMultiplet, step.initialMultiplet, comp.nuclearModel, comp.grid, 
                                                              step.settings, output=true, printout=false) 
                append!(linesA, newLines);    nt = length(linesA)
            elseif  step.process == Basics.Radiative()
                newLines = PhotoEmission.computeLinesCascade(step.finalMultiplet, step.initialMultiplet, comp.grid, 
                                                             step.settings, output=true, printout=false) 
                append!(linesR, newLines);    nt = length(linesR)
            else   error("Unsupported atomic process for cascade computations.")
            end
            sa = "     Step $st:: A total of $(length(newLines)) $(string(step.process)) lines are calculated, giving now rise " *
                 "to a total of $nt $(string(step.process)) decay lines."
            println(sa);    if  printSummary   println(iostream, sa)   end 
        end
        #
        data = Cascade.DecayData(linesR, linesA)
    end

    """
    `Cascade.determineSteps(scheme::Cascade.HollowIonScheme, comp::Cascade.Computation, capturedList::Array{Cascade.Block,1})`  
        ... determines all step::Cascade.Step's that need to be computed for this decay cascade. It cycles through all decay processes 
            of the given scheme and selects all pairs of blocks due to the selected cascade approach. It checks that at least 
            on pair of levels supports a decay within the step. A stepList::Array{Cascade.Step,1} is returned, and for which subsequently 
            all required transition amplitudes and rates/cross sections are computed.
    """
    function determineSteps(scheme::Cascade.HollowIonScheme, comp::Cascade.Computation, capturedList::Array{Cascade.Block,1})
        stepList = Cascade.Step[]
        if  comp.approach  in  [Cascade.AverageSCA(), Cascade.SCA()]
            @warn("Transition within a cascade block are not yet considered.")
            for  (ia, blocka) in enumerate(capturedList)
                for  (ib, blockb) in enumerate(capturedList)
                    if   ia == ib   continue     end
                    for  process  in  comp.scheme.processes
                        if      process == Basics.Radiative()  
                            if  blocka.NoElectrons == blockb.NoElectrons   &&
                                Basics.determineMeanEnergy(blocka.multiplet) - Basics.determineMeanEnergy(blockb.multiplet) > 0.
                                @show  Basics.determineMeanEnergy(blocka.multiplet) - Basics.determineMeanEnergy(blockb.multiplet)
                                settings = PhotoEmission.Settings(PhotoEmission.Settings(); multipoles=scheme.multipoles)
                                push!( stepList, Cascade.Step(process, settings, blocka.confs, blockb.confs, blocka.multiplet, blockb.multiplet) )
                            end
                        end
                    end
                end
            end
            #
        else  error("Unsupported cascade approach.")
        end
        return( stepList )
    end
    
    
    """
    `Cascade.generateBlocks(scheme::Cascade.HollowIonScheme, comp::Cascade.Computation, confs::Array{Configuration,1}; printout::Bool=true)`  
        ... generate all block::Cascade.Block's, that need to be computed for this electron-capture and subsequent stabilization (DR) cascade, 
            and compute also the corresponding multiplets. The different cascade approches realized different strategies how these block are 
            selected and computed. A blockList::Array{Cascade.Block,1} is returned.
    """
    function generateBlocks(scheme::Cascade.HollowIonScheme, comp::Cascade.Computation, confs::Array{Configuration,1}; printout::Bool=true)
        blockList = Cascade.Block[]
        printSummary, iostream = Defaults.getDefaults("summary flag/stream")
        #
        if    comp.approach == AverageSCA()
            sa = "\n* Generate blocks for hollow-ion cascade computations: \n" *
                 "\n  In the cascade approach $(comp.approach), the following assumptions/simplifications are made: " *
                 "\n    + orbitals are generated independently for each block for a Dirac-Fock-Slater potential; " *
                 "\n    + all blocks (multiplets) are generated from single-CSF levels and without any configuration mixing even in the SC; " *
                 "\n    + only the Coulomb interaction is considered for the electron capture. " *
                 "\n    + only E1 excitations are considered for the stabilization. \n"
            if  printout       println(sa)              end
            if  printSummary   println(iostream, sa)    end
            #
            for  confa  in confs
                print("  Multiplet computations for $(string(confa)[1:end])   with $(confa.NoElectrons) electrons ... ")
                if  printSummary   println(iostream, "\n*  Multiplet computations for $(string(confa)[1:end])   with $(confa.NoElectrons) electrons ... ")   end
                    ##x @show confa, comp.asfSettings
                    basis     = Basics.performSCF([confa], comp.nuclearModel, comp.grid, comp.asfSettings; printout=false)
                    multiplet = Basics.perform("computation: mutiplet from orbitals, no CI, CSF diagonal", [confa],  basis.orbitals, 
                                               comp.nuclearModel, comp.grid, comp.asfSettings; printout=false)
                push!( blockList, Cascade.Block(confa.NoElectrons, [confa], true, multiplet) )
                println("and $(length(multiplet.levels[1].basis.csfs)) CSF done. ")
            end
        elseif    comp.approach == SCA()  
            sa = "\n* Generate blocks for hollow-ion cascade computations: \n" *
                 "\n  In the cascade approach $(comp.approach), the following assumptions/simplifications are made: " *
                 "\n    + each single configuration forms an individual cascade block; " *
                 "\n    + orbitals are generated independently for each block for a Dirac-Fock-Slater potential; " *
                 "\n    + configuration mixing is included for each block, based on H^(DC); " *
                 "\n    + all requested multipoles are considered for the stabilization. \n"
            if  printout       println(sa)              end
            if  printSummary   println(iostream, sa)    end
            #
            for  confa  in confs
                print("  Multiplet computations for $(string(confa)[1:end])   with $(confa.NoElectrons) electrons ... ")
                if  printSummary   println(iostream, "\n*  Multiplet computations for $(string(confa)[1:end])   with $(confa.NoElectrons) electrons ... ")   end
                    basis     = Basics.performSCF([confa], comp.nuclearModel, comp.grid, comp.asfSettings; printout=false)
                    multiplet = Basics.performCI(basis,    comp.nuclearModel, comp.grid, comp.asfSettings; printout=false)
                push!( blockList, Cascade.Block(confa.NoElectrons, [confa], true, multiplet) )
                println("and $(length(multiplet.levels[1].basis.csfs)) CSF done. ")
            end
        else  error("Unsupported cascade approach.")
        end

        return( blockList )
    end


    """
    `Cascade.generateConfigurationsForDielectronicCapture(multiplets::Array{Multiplet,1},  scheme::HollowIonScheme, 
                                                      nm::Nuclear.Model, grid::Radial.Grid)`  
        ... generates all possible doubly-excited configurations due to (dielectronic) electron capture into the given multiplets.
            The number and type of such doubly-generated configurations depend on (1) the maximum (electron) energy for capturing an electron
            that is closely related to the (maximum) temperature of the plasma; (2) the fromShells from which (and how many displacements)
            are accepted as well as (3) the maximum principle and orbital angular quantum number of the additional (to-) shellsthe fromShells
            into which electrons excited and/or captured. A Tuple(initialConfList::Array{Configuration,1}, confList::Array{Configuration,1}) 
            is returned.
    """
    function generateConfigurationsForDielectronicCapture(multiplets::Array{Multiplet,1},  scheme::HollowIonScheme, 
                                                      nm::Nuclear.Model, grid::Radial.Grid)
        # Determine all (reference) configurations from multiplets and generate the 'excited' configurations due to the specificed excitations
        initialConfList = Configuration[]
        for mp  in  multiplets   
            confList = Basics.extractNonrelativisticConfigurations(mp.levels[1].basis)
            for  conf in confList   if  conf in initialConfList   nothing   else   push!(initialConfList, conf)      end      end
        end
        captureConfList = copy(initialConfList)
        for nc = 1:scheme.NoCapturedElectrons
            captureConfList = Basics.generateConfigurationsWithElectronCapture(captureConfList, Shell[], scheme.intoShells, 0);   @show nc, captureConfList
        end
        shellList       = Basics.extractNonrelativisticShellList(multiplets)
        shellList       = Basics.merge(scheme.intoShells, scheme.decayShells);  @show shellList
        blockConfList   = copy(initialConfList)
        for nc = 1:scheme.NoCapturedElectrons
            blockConfList   = Basics.generateConfigurationsWithElectronCapture(blockConfList, Shell[], shellList, 0);   @show nc, blockConfList
        end
        @show initialConfList
        @show blockConfList
        @warn("blockConfList does not yet support the autoionization of the high-n electrons.")
        #
        # Determine first a hydrogenic spectrum for all subshells of the initial and doubly-excited states
        allConfList   = Configuration[];      append!(allConfList, initialConfList);      append!(allConfList, blockConfList)
        allSubshells  = Basics.extractRelativisticSubshellList(allConfList)
        primitives    = Bsplines.generatePrimitives(grid)
        orbitals      = Bsplines.generateOrbitalsHydrogenic(primitives, nm, allSubshells, printout=true)
        # Exclude configurations with too high mean energies
        en            = Float64[];   
        for conf in initialConfList
            wen = Basics.determineMeanEnergy(conf, orbitals, nm, grid)
            push!(en, wen)
        end
        initialMean = sum(en) / length(en)
        println(">>> initial configuration(s) have mena energies  $initialMean  [a.u.].")

        return( (initialConfList, blockConfList)  )
    end


    """
    `Cascade.perform(scheme::HollowIonScheme, comp::Cascade.Computation)`  
        ... to set-up and perform a dielectronic-recombination (DR) plasma rate coefficient computation that combines the electron capture
            and the subsequent radiative stabilization steps. Such a computation starts from a given set of initial configurations xor 
            initial multiplets and (1) generates all doubly-excited configurations due to the capture of an electron with a given maximum
            electron energy; (2) selects all electron capture (inverse Auger) and re-autoionization (Auger) steps and (3) selects
            all steps for radiative stabilization due to given parameters of the scheme::HollowIonScheme. The results of 
            these DR plasma rate computation are comprised into (output) data::ExcitationData, while these data are only printed during 
            the generation and nothing is returned.

    `Cascade.perform(scheme::HollowIonScheme, comp::Cascade.Computation; output=true, outputToFile::Bool=true)`   
        ... to perform the same but to return the complete output in a dictionary that is written to disk and can be used in subsequent
            cascade simulation. The particular output depends on the specifications of the cascade.
    """
    function perform(scheme::HollowIonScheme, comp::Cascade.Computation; output::Bool=false, outputToFile::Bool=true)
        if  output    results = Dict{String, Any}()    else    results = nothing    end
        printSummary, iostream = Defaults.getDefaults("summary flag/stream")
        #
        # Perform the SCF and CI computation for the intial-state multiplets if initial configurations are given
        if  comp.initialConfigs != Configuration[]
            basis      = Basics.performSCF(comp.initialConfigs, comp.nuclearModel, comp.grid, comp.asfSettings; printout=false)
            multiplet  = Basics.performCI(basis, comp.nuclearModel, comp.grid, comp.asfSettings; printout=false)
            multiplets = [Multiplet("initial states", multiplet.levels)]
        else
            multiplets = comp.initialMultiplets
        end
        # Print out initial configurations and levels 
        Cascade.displayLevels(stdout, multiplets, sa="initial ")
        if  printSummary   Cascade.displayLevels(iostream, multiplets, sa="initial ")                            end
        #
        # Generate subsequent cascade configurations as well as display and group them together
        wa  = Cascade.generateConfigurationsForDielectronicCapture(multiplets, comp.scheme, comp.nuclearModel, comp.grid)
        ##x wb1 = Cascade.groupDisplayConfigurationList(comp.nuclearModel.Z, wa[1], sa="(initial part of the) electron capture ")
        wb2 = Cascade.groupDisplayConfigurationList(comp.nuclearModel.Z, wa[2], sa="hollow ion configurations ")
        #
        # Determine first all configuration 'blocks' and from them the individual steps of the cascade
        ##x wc1 = Cascade.generateBlocks(scheme, comp::Cascade.Computation, wb1)
        wc2 = Cascade.generateBlocks(scheme, comp::Cascade.Computation, wb2, printout=false)
        ##x Cascade.displayBlocks(stdout, wc1, sa="for the (initial part of the) excited cascade ");      
        Cascade.displayBlocks(stdout, wc2, sa="for the hollow ion cascade ")
        if  printSummary   ##x Cascade.displayBlocks(iostream, wc1, sa="for the (initial part of the) excited cascade ")
                           Cascade.displayBlocks(iostream, wc2, sa="for the hollow ion cascade ")    end      
        #
        # Determine, modify and compute the transition data for all steps, ie. the PhotoIonization.Line's, etc.
        gMultiplets = Multiplet[];     for block in wc2  push!(gMultiplets, block.multiplet)    end
        ##x we = Cascade.determineSteps(scheme, comp, wc1, wc2)
        we = Cascade.determineSteps(scheme, comp, wc2)
        Cascade.displaySteps(stdout, we, sa="hollow ion decay ")
        if  printSummary   Cascade.displaySteps(iostream, we, sa="hollow ion decay ")    end      
        wf   = Cascade.modifySteps(we)
        #
        data = Cascade.computeSteps(scheme, comp, wf)
        if output    
            results = Base.merge( results, Dict("name"                                  => comp.name) ) 
            results = Base.merge( results, Dict("cascade scheme"                        => comp.scheme) ) 
            results = Base.merge( results, Dict("initial multiplets:"                   => multiplets) )    
            results = Base.merge( results, Dict("generated multiplets:"                 => gMultiplets) )    
            results = Base.merge( results, Dict("hollow-ion line data:" => data) )
            #
            #  Write out the result to file to later continue with simulations on the cascade data
            filename = "zzz-cascade-hollow-ion-computations-" * string(Dates.now())[1:13] * ".jld"
            println("\n* Write all results to disk; use:\n   JLD.save(''$filename'', results) \n   using JLD " *
                    "\n   results = JLD.load(''$filename'')    ... to load the results back from file.")
            if  printSummary   println(iostream, "\n* Write all results to disk; use:\n   JLD.save(''$filename'', results) \n   using JLD " *
                                                 "\n   results = JLD.load(''$filename'')    ... to load the results back from file." )      end      
            JLD2.@save filename results
        end
        ## return( results )
        return( results )
    end
