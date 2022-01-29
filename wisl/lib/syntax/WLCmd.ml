open VisitorUtils

type tt =
  | Fold of string * WLExpr.t list
  | Unfold of string * WLExpr.t list
  | ApplyLem of string * WLExpr.t list * string list
  | LogicIf of WLExpr.t * t list * t list
  | Assert of WLAssert.t * string list
  | Invariant of WLAssert.t * string list

and t = { wlcnode : tt; wlcid : int; wlcloc : CodeLoc.t }

let get lcmd = lcmd.wlcnode
let get_id lcmd = lcmd.wlcid
let get_loc lcmd = lcmd.wlcloc

let make bare_lcmd loc =
  { wlcnode = bare_lcmd; wlcloc = loc; wlcid = Generators.gen_id () }

let is_inv lcmd =
  match get lcmd with
  | Invariant _ -> true
  | _ -> false

let is_fold lcmd =
  match get lcmd with
  | Fold _ -> true
  | _ -> false

let is_unfold lcmd =
  match get lcmd with
  | Unfold _ -> true
  | _ -> false

let rec get_by_id id lcmd =
  let lexpr_getter = WLExpr.get_by_id id in
  let lexpr_list_visitor = list_visitor_builder WLExpr.get_by_id id in
  let list_visitor = list_visitor_builder get_by_id id in
  let lassert_getter = WLAssert.get_by_id id in
  let aux lcmdp =
    match get lcmdp with
    | Fold (_, lel) | Unfold (_, lel) | ApplyLem (_, lel, _) ->
        lexpr_list_visitor lel
    | LogicIf (le, lcmdl1, lcmdl2) ->
        lexpr_getter le |>> (list_visitor, lcmdl1) |>> (list_visitor, lcmdl2)
    | Assert (la, _) | Invariant (la, _) -> lassert_getter la
  in
  let self_or_none = if get_id lcmd = id then `WLCmd lcmd else `None in
  self_or_none |>> (aux, lcmd)

(* TODO: write pretty_print function *)
let pp fmt lcmd =
  let fprintf = Format.fprintf fmt in
  match get lcmd with
  | Fold (pname, wlel) ->
      fprintf "fold %s(%a)" pname (WPrettyUtils.pp_list WLExpr.pp) wlel
  | Unfold (pname, wlel) ->
      fprintf "unfold %s(%a)" pname (WPrettyUtils.pp_list WLExpr.pp) wlel
  | ApplyLem (lname, wlel, _) ->
      fprintf "apply %s(%a)" lname (WPrettyUtils.pp_list WLExpr.pp) wlel
  (* | Assert (a, b) -> fprintf "%a"  WLAssert.pp a
     | Invariant (a, b) ->
       let existentials = match b with
         |[] -> ""
         | _ -> Format.asprintf "{exists: %a}" (WPrettyUtils.pp_list Format.pp_print_string) b
       in
       fprintf "invariant %s %a" existentials WLAssert.pp a *)
  | _ -> Format.fprintf fmt "[LOGIC COMMAND]"

let str = Format.asprintf "%a" pp

let rec substitution subst { wlcnode; wlcid; wlcloc } =
  let f = substitution subst in
  let fa = WLAssert.substitution subst in
  let fe = WLExpr.substitution subst in
  let wlcnode =
    match wlcnode with
    | Fold (pname, les) -> Fold (pname, List.map fe les)
    | Unfold (pname, les) -> Unfold (pname, List.map fe les)
    | ApplyLem (lname, les, binders) ->
        ApplyLem (lname, List.map fe les, binders)
    | LogicIf (le, cmds_t, cmds_e) ->
        LogicIf (fe le, List.map f cmds_t, List.map f cmds_e)
    | Assert (la, binders) -> Assert (fa la, binders)
    | Invariant (la, binders) -> Invariant (fa la, binders)
  in
  { wlcnode; wlcid; wlcloc }
