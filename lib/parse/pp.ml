(**
   Pretty-printer the [Ast.t]
*)

module P = Ast
module T = Common.Type_annotations
module F = Format

let drop_loc = Common.Location.With_loc.description
let (%>) f g x = g (f x)

let pp_ident = F.pp_print_string
let kwd   = F.pp_print_string

let pp_option printer (fmt : F.formatter) = CCOpt.iter (fun x -> printer fmt x)

let const fmt = function
  | P.Cbool b -> F.pp_print_bool fmt b
  | P.Cint i-> F.pp_print_int  fmt i
  | P.Cstring s -> F.fprintf fmt "\"%s\"" s
  | P.Cpath s -> CCFormat.string fmt s
  | P.Cbracketed s ->
    CCFormat.fprintf fmt "<%s>" s

let pp_binop fmt = function
  | P.Ocons -> F.pp_print_string fmt "::"
  | P.Oeq   -> F.pp_print_string fmt "=="
  | P.OnonEq   -> F.pp_print_string fmt "!="
  | P.Oplus  -> F.pp_print_string fmt "+"
  | P.Ominus -> F.pp_print_string fmt "-"
  | P.Oand   -> F.pp_print_string fmt "&&"
  | P.Oor    -> F.pp_print_string fmt "||"
  | P.Oimplies -> F.pp_print_string fmt "->"
  | P.Omerge -> F.pp_print_string fmt "//"
  | P.Oconcat -> F.pp_print_string fmt "++"

and pp_monop fmt = function
  | P.Onot   -> F.pp_print_string fmt "!"
  | P.Oneg  -> F.pp_print_string fmt "-"

let rec pp_expr fmt = drop_loc %> function
    | P.Evar v ->
      pp_ident fmt v
    | P.Econstant c ->
      const fmt c
    | P.Elambda (p, e) ->
      F.fprintf fmt "@[<2>(%a:@ %a)@]"
        pp_pattern p
        pp_expr e
    | P.EfunApp (e1, e2) ->
      F.fprintf fmt "(@[%a@ %a@])"
        pp_expr e1
        pp_expr e2
    | P.EtyAnnot (e, ty) ->
      F.fprintf fmt "@[(%a %a)@]"
        pp_expr e
        pp_type_annot ty
    | P.Ebinop (op, e1, e2) ->
      F.fprintf fmt "@[(%a %a %a)@]"
        pp_expr e1
        pp_binop op
        pp_expr e2
    | P.Emonop (op, e) ->
      F.fprintf fmt "@[(%a%a)@]"
        pp_monop op
        pp_expr e
    | P.Elet (bindings, e) ->
      F.fprintf fmt "@[let %ain@;%a@]"
        pp_bindings bindings
        pp_expr e
    | P.Erecord r -> pp_record fmt r
    | P.Epragma (pragma, e) ->
      F.fprintf fmt "#:: %a\n%a"
        Pragma.pp pragma
        pp_expr e
    | P.Eite (eif, ethen, eelse) ->
      F.fprintf fmt "@[if (%a)@;then@ %a@;else@ %a@]"
        pp_expr eif
        pp_expr ethen
        pp_expr eelse
    | P.Eaccess (e, ap, default) ->
      F.fprintf fmt "%a.%a%a"
        pp_expr e
        pp_ap ap
        pp_access_guard default
    | P.EtestMember (e, ap) ->
      F.fprintf fmt "%a ? %a"
        pp_expr e
        pp_ap ap
    | P.Ewith (e1, e2) ->
      F.fprintf fmt "with %a; %a"
        pp_expr e1
        pp_expr e2

and pp_ap fmt = F.pp_print_list
    ~pp_sep:(fun fmt () -> F.pp_print_char fmt '.')
    pp_ap_field
    fmt

and pp_ap_field fmt = drop_loc %> function
    | P.AFexpr e ->
      F.fprintf fmt "${%a}" pp_expr e
    | P.AFidentifier s -> F.pp_print_string fmt s

and pp_pattern fmt = drop_loc %> function
    | P.Pvar (v, a) -> pp_pattern_var fmt (v, a)
    | P.Pnontrivial (sub_pattern, alias) ->
      pp_nontrivial_pattern fmt sub_pattern;
      pp_option (fun fmt var -> F.fprintf fmt "@%s" var) fmt alias

and pp_pattern_var fmt = function
  | (v, None) -> pp_ident fmt v
  | (v, Some t) ->
    F.fprintf fmt "%a %a"
      pp_ident v
      pp_type_annot   t

and pp_pattern_ap fmt = function
  | (v, None) -> pp_ap fmt v
  | (v, Some t) ->
    F.fprintf fmt "%a %a"
      pp_ap v
      pp_type_annot   t

and pp_nontrivial_pattern fmt = function
  | P.NPrecord ([], P.Open) ->
    F.pp_print_string fmt "{ ... }"
  | P.NPrecord (fields, open_flag) ->
    F.fprintf fmt "{ %a%s }"
      pp_pat_record_fields fields
      (match open_flag with
       | P.Closed -> ""
       | P.Open -> ", ...")

and pp_pat_record_fields fmt = function
  | [] -> ()
  | [f] -> pp_pat_record_field fmt f
  | f::tl ->
    pp_pat_record_field fmt f;
    F.pp_print_string fmt ", ";
    pp_pat_record_fields fmt tl

and pp_pat_record_field fmt = function
  | { P.field_name; default_value; type_annot; } ->
    F.fprintf fmt "%a%a%a"
      pp_ident field_name
      (pp_option (fun fmt -> F.fprintf fmt " ? %a" pp_expr)) default_value
      (pp_option (fun fmt -> F.fprintf fmt " %a" pp_type_annot)) type_annot

and pp_type_annot fmt = F.fprintf fmt "/*: %a */" pp_typ

and pp_typ fmt = T.pp fmt

and pp_op_args fmt = function
  | [] -> ()
  | [a] ->
    pp_expr fmt a
  | a::tl ->
    F.fprintf fmt "%a,@ %a"
      pp_expr a
      pp_op_args tl

and pp_record fmt { P.recursive; fields } =
  if recursive then F.pp_print_string fmt "rec ";
  F.fprintf fmt "@[{@ %a@]}"
    (fun fmt -> List.iter (pp_record_field fmt)) fields

and pp_record_field fmt = drop_loc %> function
    | P.Fdef (ap, value) ->
      F.fprintf fmt "%a = %a;@ "
        pp_pattern_ap ap
        pp_expr value
    | P.Finherit (base_expr, fields) ->
      F.fprintf fmt "inherit %a%a;@ "
        (pp_option pp_base_expr) base_expr
        pp_fields fields

and pp_base_expr fmt = F.fprintf fmt "(%a) " pp_expr

and pp_fields fmt =
  F.pp_print_list
    ~pp_sep:F.pp_print_space
    (fun fmt -> drop_loc %> F.pp_print_string fmt)
    fmt

and pp_bindings fmt =
  Format.pp_print_list
    ~pp_sep:(fun _ () -> ())
    pp_binding
    fmt

and pp_binding fmt = pp_record_field fmt

and pp_access_guard fmt = function
  | Some guard -> CCFormat.fprintf fmt " or %a" pp_expr guard
  | None -> CCFormat.silent fmt ()
