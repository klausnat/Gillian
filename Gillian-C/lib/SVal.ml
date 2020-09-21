open Gil_syntax
open Gillian.Symbolic

let ( let* ) = Option.bind

let ( let+ ) o f = Option.map f o

type t =
  | SUndefined
  | Sptr       of string * Expr.t
  | SVint      of Expr.t
  | SVlong     of Expr.t
  | SVsingle   of Expr.t
  | SVfloat    of Expr.t

let equal a b =
  match (a, b) with
  | SUndefined, SUndefined -> true
  | Sptr (la, oa), Sptr (lb, ob) when String.equal la lb && Expr.equal oa ob ->
      true
  | SVint a, SVint b when Expr.equal a b -> true
  | SVlong a, SVlong b when Expr.equal a b -> true
  | SVsingle a, SVsingle b when Expr.equal a b -> true
  | SVfloat a, SVfloat b when Expr.equal a b -> true
  | _, _ -> false

type typ = Compcert.AST.typ =
  | Tint
  | Tfloat
  | Tlong
  | Tsingle
  | Tany32
  | Tany64

let tptr = Compcert.AST.coq_Tptr

let is_loc gamma loc =
  let r_opt =
    let* loc_t = TypEnv.get gamma loc in
    match loc_t with
    | Type.ObjectType -> Some true
    | _               -> Some false
  in
  Option.value ~default:false r_opt

let is_zero = function
  | SVint (Lit (Num 0.))
  | SVlong (Lit (Num 0.))
  | SVsingle (Lit (Num 0.))
  | SVfloat (Lit (Num 0.)) -> true
  | _ -> false

let zero_of_chunk chunk =
  match Compcert.AST.type_of_chunk chunk with
  | Tany32 | Tint  -> SVint (Lit (Num 0.))
  | Tany64 | Tlong -> SVlong (Lit (Num 0.))
  | Tsingle        -> SVsingle (Lit (Num 0.))
  | Tfloat         -> SVfloat (Lit (Num 0.))

let is_loc_ofs gamma loc ofs =
  let r_opt =
    let* loc_t = TypEnv.get gamma loc in
    let* ofs_t = TypEnv.get gamma ofs in
    match (loc_t, ofs_t) with
    | Type.ObjectType, Type.NumberType -> Some true
    | _ -> Some false
  in
  Option.value ~default:false r_opt

let of_gil_expr_almost_concrete ?(gamma = TypEnv.init ()) gexpr =
  let open Expr in
  let open CConstants.VTypes in
  match gexpr with
  | Lit Undefined -> Some (SUndefined, [])
  | EList [ ALoc loc; offset ] | EList [ Lit (Loc loc); offset ] ->
      Some (Sptr (loc, offset), [])
  | EList [ LVar loc; Lit (Num k) ] when is_loc gamma loc ->
      let aloc = ALoc.alloc () in
      let new_pf = Formula.Eq (LVar loc, Expr.ALoc aloc) in
      Some (Sptr (aloc, Lit (Num k)), [ new_pf ])
  | EList [ LVar loc; LVar ofs ] when is_loc_ofs gamma loc ofs ->
      let aloc = ALoc.alloc () in
      let new_pf = Formula.Eq (LVar loc, Expr.ALoc aloc) in
      Some (Sptr (aloc, LVar ofs), [ new_pf ])
  | EList [ Lit (String typ); value ] when String.equal typ int_type ->
      Some (SVint value, [])
  | EList [ Lit (String typ); value ] when String.equal typ float_type ->
      Some (SVfloat value, [])
  | EList [ Lit (String typ); value ] when String.equal typ single_type ->
      Some (SVsingle value, [])
  | EList [ Lit (String typ); value ] when String.equal typ long_type ->
      Some (SVlong value, [])
  | _ -> None

let of_gil_expr ?(pfs = PureContext.init ()) ?(gamma = TypEnv.init ()) sval_e =
  Logging.verbose (fun fmt -> fmt "OF_GIL_EXPR : %a" Expr.pp sval_e);
  let possible_exprs =
    sval_e :: FOLogic.Reduction.get_equal_expressions pfs sval_e
  in
  List.fold_left
    (fun ac exp ->
      Logging.verbose (fun fmt -> fmt "TRYING SUBSTITUTE EXPR : %a" Expr.pp exp);
      match ac with
      | None -> of_gil_expr_almost_concrete ~gamma exp
      | _    -> ac)
    None possible_exprs

let of_gil_expr_exn ?(pfs = PureContext.init ()) ?(gamma = TypEnv.init ()) gexp
    =
  match of_gil_expr ~pfs ~gamma gexp with
  | Some s -> s
  | None   ->
      failwith
        (Format.asprintf
           "The following expression does not seem to correspond to any \
            compcert value : %a"
           Expr.pp gexp)

let to_gil_expr gexpr =
  let open Expr in
  let open CConstants.VTypes in
  match gexpr with
  | SUndefined              -> (Lit Undefined, [])
  | Sptr (loc_name, offset) ->
      let loc = loc_from_loc_name loc_name in
      ( EList [ loc; offset ],
        [ (loc, Type.ObjectType); (offset, Type.NumberType) ] )
  | SVint n                 -> ( EList [ Lit (String int_type); n ],
                                 [ (n, Type.NumberType) ] )
  | SVlong n                -> ( EList [ Lit (String long_type); n ],
                                 [ (n, Type.NumberType) ] )
  | SVfloat n               -> ( EList [ Lit (String float_type); n ],
                                 [ (n, Type.NumberType) ] )
  | SVsingle n              ->
      (EList [ Lit (String single_type); n ], [ (n, Type.NumberType) ])

let pp fmt v =
  let se = Expr.pp in
  let f = Format.fprintf in
  match v with
  | SUndefined    -> f fmt "undefined"
  | Sptr (l, ofs) -> f fmt "Ptr(%s, %a)" l se ofs
  | SVint i       -> f fmt "Int(%a)" se i
  | SVlong i      -> f fmt "Long(%a)" se i
  | SVfloat i     -> f fmt "Float(%a)" se i
  | SVsingle i    -> f fmt "Single(%a)" se i