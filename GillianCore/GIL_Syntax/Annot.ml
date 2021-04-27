(** {b GIL annot}. *)
type t = {
  origin_loc : Location.t option;  (** Better not to know what this is for *)
  origin_id : int;  (** Origin Id, that should be abstracted away *)
  loop_info : string list;
}

(**/**)

let make ?origin_loc ?(origin_id = -1) ?(loop_info = []) () =
  { origin_loc; origin_id; loop_info }

let get_loop_info (annot : t) = annot.loop_info

let set_loop_info (annot : t) (loop_info : string list) =
  { annot with loop_info }

let get_origin_loc annot = annot.origin_loc
