open Gil_syntax
module PureContext = Engine.PFS
module TypEnv = Engine.TypEnv
module FOSolver = Engine.FOSolver

type t = {
  pfs : PureContext.t;
  gamma : TypEnv.t;
  learned : Formula.Set.t;
  learned_types : (string * Type.t) list;
  unification : bool;
}

let copy { pfs; gamma; learned; learned_types; unification } =
  {
    pfs = PureContext.copy pfs;
    gamma = TypEnv.copy gamma;
    learned;
    learned_types;
    unification;
  }

let make
    ~pfs ~gamma ?(unification = false) ?(learned = []) ?(learned_types = []) ()
    =
  {
    pfs;
    gamma;
    learned = Formula.Set.of_list learned;
    learned_types;
    unification;
  }

let init ?(unification = false) () =
  make ~pfs:(PureContext.init ()) ~gamma:(TypEnv.init ()) ~unification ()

let empty = init ()

let pfs_to_pfs_and_gamma pfs =
  let expr_type_binding_to_gamma etb =
    match etb with
    | Expr.PVar s, t | Expr.LVar s, t -> Some (s, t)
    | _ -> None
  in
  let rec aux = function
    | [] -> ([], [])
    | Formula.Eq (UnOp (TypeOf, e), Lit (Type t)) :: r
    | Eq (Lit (Type t), UnOp (TypeOf, e)) :: r -> (
        let other_pfs, other_gamma = aux r in
        match expr_type_binding_to_gamma (e, t) with
        | None       ->
            ( Formula.Eq (Lit (Type t), UnOp (TypeOf, e)) :: other_pfs,
              other_gamma )
        | Some gamma -> (other_pfs, gamma :: other_gamma))
    | f :: r ->
        let other_pfs, other_gamma = aux r in
        (f :: other_pfs, other_gamma)
  in
  aux pfs

let extend pc fs =
  let fs = List.concat_map Formula.split_conjunct_formulae fs in
  let pfs, gamma = (pc.pfs, pc.gamma) in
  let fs =
    List.filter_map
      (fun f ->
        match
          Engine.Reduction.reduce_formula ~unification:pc.unification ~pfs
            ~gamma f
        with
        | Formula.True -> None
        | f            -> Some f)
      fs
  in
  let new_pfs, new_gamma = pfs_to_pfs_and_gamma fs in
  {
    pc with
    learned = Formula.Set.add_seq (List.to_seq new_pfs) pc.learned;
    learned_types = new_gamma @ pc.learned_types;
  }

let extend_types pc types = { pc with learned_types = types @ pc.learned_types }

let equal pca pcb =
  pca.pfs = pcb.pfs && pca.gamma = pcb.gamma
  && Formula.Set.equal pca.learned pcb.learned
  && List.for_all2
       (fun (n1, t1) (n2, t2) ->
         String.equal n1 n2 && String.equal (Type.str t1) (Type.str t2))
       pca.learned_types pcb.learned_types

let pp =
  Fmt.braces
    (Fmt.record ~sep:Fmt.semi
       [
         Fmt.field "pfs"
           (fun x -> x.pfs)
           (fun fmt pfs ->
             (Fmt.Dump.list Formula.pp) fmt (PureContext.to_list pfs));
         Fmt.field "gamma" (fun x -> x.gamma) TypEnv.pp;
         Fmt.field "learned"
           (fun x -> Formula.Set.to_seq x.learned)
           (Fmt.Dump.seq Formula.pp);
         Fmt.field "learned_types"
           (fun x -> x.learned_types)
           (Fmt.Dump.list
              (Fmt.Dump.pair Fmt.string (Fmt.of_to_string Type.str)));
       ])

let diff pca pcb =
  ( Formula.Set.diff pca.learned pcb.learned,
    Formula.Set.diff pcb.learned pca.learned )
