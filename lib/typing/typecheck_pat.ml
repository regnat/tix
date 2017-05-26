module T = Typed_ast
module P = Simple.Ast
module Env = Typing_env

module L = Parse.Location.With_loc

let infer_pattern_descr = function
  (* | P.Pvar (v, maybe_t) -> *)
  (*   let t = CCOpt.get Type_annotations.(BaseType Gradual) maybe_t in *)
  (*   (Env.singleton v t, { T.With_type.description = T.Pvar v; typ = t; }) *)
  | _ -> failwith "TODO"

let infer_pattern { L.description; location } =
  let (env, descr) = infer_pattern_descr description in
  (env, { L.description = descr; location })

let infer : P.pattern -> (Env.t * T.pattern) = infer_pattern