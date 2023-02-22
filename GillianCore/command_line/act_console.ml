open Cmdliner
open Command_line_utils
module L = Logging

module Make
    (ID : Init_data.S)
    (PC : ParserAndCompiler.S with type init_data = ID.t)
    (Abductor : Abductor.S
                  with type init_data = ID.t
                   and type annot = PC.Annot.t)
    (Gil_parsing : Gil_parsing.S with type annot = PC.Annot.t) : Console.S =
struct
  module Common_args = Common_args.Make (PC)
  open Common_args

  let emit_specs =
    let doc =
      "Emit the final GIL program containing all the derived specifications."
    in
    Arg.(value & flag & info [ "emit-specs" ] ~doc)

  let specs_to_stdout =
    let doc = "Emit specs to stdout, useful for testing." in
    Arg.(value & flag & info [ "specs-to-stdout" ] ~doc)

  let process_files files already_compiled outfile_opt emit_specs incremental =
    let file = List.hd files in
    let e_prog, init_data, source_files_opt =
      if not already_compiled then
        let () =
          L.verbose (fun m ->
              m
                "@\n\
                 *** Stage 1: Parsing program in original language and \
                 compiling to Gil. ***@\n")
        in
        let progs =
          ParserAndCompiler.get_progs_or_fail PC.pp_err
            (PC.parse_and_compile_files files)
        in
        let e_progs = progs.gil_progs in
        let () = Gil_parsing.cache_labelled_progs (List.tl e_progs) in
        let e_prog = snd (List.hd e_progs) in
        let source_files = progs.source_files in
        (e_prog, progs.init_data, Some source_files)
      else
        let () =
          L.verbose (fun m -> m "@\n*** Stage 1: Parsing Gil program. ***@\n")
        in
        let Gil_parsing.{ labeled_prog; init_data } =
          Gil_parsing.parse_eprog_from_file file
        in
        let init_data =
          match ID.of_yojson init_data with
          | Ok d -> d
          | Error e -> failwith e
        in
        (labeled_prog, init_data, None)
    in
    let () =
      burn_gil ~init_data:(ID.to_yojson init_data) ~pp_prog:Prog.pp_labeled
        e_prog outfile_opt
    in
    let () =
      L.normal (fun m -> m "*** Stage 2: Transforming the program.@\n")
    in
    let prog =
      Gil_parsing.eprog_to_prog
        ~other_imports:(convert_other_imports PC.other_imports)
        e_prog
    in
    let () =
      L.normal (fun m -> m "@\n*** Stage 2: DONE transforming the program.@\n")
    in
    let () = L.normal (fun m -> m "*** Stage 3: Symbolic Execution.@\n") in
    let () = Config.unfolding := false in
    let prog = LogicPreprocessing.preprocess prog true in
    match UP.init_prog prog with
    | Error _ -> failwith "Creation of unification plans failed."
    | Ok prog' ->
        let () =
          Abductor.test_prog ~init_data prog' incremental source_files_opt
        in
        if emit_specs then
          let () = Prog.update_specs e_prog prog'.prog in
          let fname = Filename.chop_extension (Filename.basename file) in
          let dirname = Filename.dirname file in
          let out_path = Filename.concat dirname (fname ^ "_bi.gil") in
          Io_utils.save_file_pp out_path Prog.pp_labeled e_prog

  let act
      files
      already_compiled
      outfile_opt
      no_heap
      stats
      parallel
      emit_specs
      specs_to_stdout
      incremental
      bi_unroll_depth
      bi_no_spec_depth
      () =
    let () = Config.current_exec_mode := BiAbduction in
    let () = PC.initialize BiAbduction in
    let () = Config.stats := stats in
    let () = Config.no_heap := no_heap in
    let () = Config.parallel := parallel in
    let () = Config.bi_unroll_depth := bi_unroll_depth in
    let () = Config.bi_no_spec_depth := bi_no_spec_depth in
    let () = Config.specs_to_stdout := specs_to_stdout in
    let () =
      process_files files already_compiled outfile_opt emit_specs incremental
    in
    let () = if !Config.stats then Statistics.print_statistics () in
    Logging.wrap_up ()

  let act_t =
    Term.(
      const act $ files $ already_compiled $ output_gil $ no_heap $ stats
      $ parallel $ emit_specs $ specs_to_stdout $ incremental $ bi_unroll_depth
      $ bi_no_spec_depth)

  let act_info =
    let doc =
      "Automatic Compositional Testing of a file of the target language"
    in
    let man =
      [
        `S Manpage.s_description;
        `P
          "Uses Automatic Compositional Testing on a given file, after \
           compiling it to GIL";
      ]
    in
    Cmd.info "act" ~doc ~man

  let act_cmd = Cmd.v act_info (Common_args.use act_t)
  let cmds = [ act_cmd ]
end
