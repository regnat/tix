module P = Simple.Ast
module TE = Typing_env

module L = Parse.Location.With_loc

let infer_pattern_descr ?t_constr tenv p = match p with
  | P.Pvar (v, maybe_t) ->
    let t =
      match t_constr, maybe_t with
      | None, None -> Types.Builtins.grad
      | _, _ ->
        let real_constraint = CCOpt.get_or ~default:Types.Builtins.any t_constr
        and annoted =
          CCOpt.fold
            (fun _ annot -> Annotations.to_type tenv annot)
            (Some Types.Builtins.any)
            maybe_t
          |> CCOpt.get_lazy (fun () -> assert false)
        in
        Types.Builtins.cap real_constraint annoted
    in
    (TE.singleton v t, t)
  | _ -> failwith "TODO"

let infer_pattern ?t_constr tenv { L.description; _ } =
  infer_pattern_descr ?t_constr tenv description

let infer : ?t_constr:Types.t
  -> Types.Environment.t
  -> P.pattern
  -> (TE.t * Types.t) =
  infer_pattern
