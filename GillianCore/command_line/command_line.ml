open Cmdliner
module ParserAndCompiler = ParserAndCompiler

module Make
    (ID : Init_data.S)
    (CMemory : CMemory.S with type init_data = ID.t)
    (SMemory : SMemory.S with type init_data = ID.t)
    (PC : ParserAndCompiler.S with type init_data = ID.t)
    (External : External.T(PC.Annot).S)
    (Runners : Runners.S)
    (Lifter : functor
      (V : Verifier.S with type annot = PC.Annot.t)
      ->
      Debugger_lifter.S
        with type memory = SMemory.t
         and type memory_error = SMemory.err_t
         and type tl_ast = PC.tl_ast
         and type cmd_report = V.SAInterpreter.Logging.ConfigReport.t
         and type annot = PC.Annot.t) =
struct
  module Gil_parsing = Gil_parsing.Make (PC.Annot)
  module CState = CState.Make (CMemory)

  module CInterpreter =
    GInterpreter.Make (CVal.M) (CVal.CESubst) (CStore) (CState) (PC) (External)

  module SState = SState.Make (SMemory)

  module SInterpreter =
    GInterpreter.Make (SVal.M) (SVal.SESubst) (SStore) (SState) (PC) (External)

  module SPState =
    PState.Make (SVal.M) (SVal.SESubst) (SStore) (SState) (Preds.SPreds)

  module Verification = Verifier.Make (SState) (SPState) (PC) (External)
  module Lifter = Lifter (Verification)
  module Abductor = Abductor.Make (SPState) (PC) (External)
  module Debugger = Debugger.Make (ID) (PC) (Verification) (Lifter)
  module Debug_adapter = Debug_adapter.Make (Debugger)

  let main () =
    let doc = "An analysis toolchain" in

    let man =
      [
        `S Manpage.s_description;
        `P "Analysis toolchain for a given language, based on Gillian";
      ]
    in
    let info = Cmd.info (Filename.basename Sys.executable_name) ~doc ~man in

    let consoles : (module Console.S) list =
      [
        (module Compiler_console.Make (PC));
        (module C_interpreter_console.Make (ID) (PC) (CState) (CInterpreter)
                  (Gil_parsing));
        (module S_interpreter_console.Make (ID) (PC) (SState) (SInterpreter)
                  (Gil_parsing));
        (module Verification_console.Make (ID) (PC) (Verification) (Gil_parsing));
        (module Act_console.Make (ID) (PC) (Abductor) (Gil_parsing));
        (module Debug_verification_console.Make (PC) (Debug_adapter));
        (module Bulk_console.Make (PC) (Runners));
      ]
    in
    let cmds =
      consoles |> List.concat_map (fun (module C : Console.S) -> C.cmds)
    in
    exit (Cmd.eval (Cmd.group info cmds))
end