open OUnit2

exception ParseError

let test_parse_pp_str ?(isTodo=false) input expected_output _ =
  if isTodo then todo "Not implemented yet";
  let output =
    begin
      match Parse.Parser.parse_string Parse.Parser.expr input with
      | Ok s -> Parse.Pp.pp_expr Format.str_formatter s;
      | Error (msg, _) ->
        output_string stderr msg;
        raise ParseError
    end;
    Format.flush_str_formatter ()
  in
  assert_equal
    ~printer:(fun x -> x)
    expected_output
    output

let isTodo = true (* To use [~isTodo] as a shortcut for [~isTodo=true] *)

let testsuite =
  "onix_parser">:::
  List.map (fun (name, input, output) ->
      name >:: test_parse_pp_str input output)
    [
      "test_var", "x", "x";
      "test_const_int", "1234", "1234";
      "test_const_true", "true", "true";
      "test_const_false", "false", "false";
      "test_lambda", "x: x", "(x: x)";
      "test_app", "x y", "(x y)";
      "test_multi_app", "x y z w", "(((x y) z) w)";
      "test_multi_app_2", "x y (z w)", "((x y) (z w))";
      "test_lambda_app", "(x: y) z", "((x: y) z)";
      "test_app_lambda", "x: y z", "(x: (y z))";
      "test_annotated_pattern", "x /*: int */: x", "(x /*: int */: x)";
      "test_Y_comb", "(x: x x) (x: x x)", "((x: (x x)) (x: (x x)))";
      "test_annot", "(x /*: int */)", "(x /*: int */)";
      "test_annot_arrow", "(x /*: int -> int */)", "(x /*: (int) -> int */)";
      "test_arith", "x + y - z + (- a)", "(((x + y) - z) + (-a))";
      "test_string", "\"x\"", "\"x\"";
      "test_comment", "1 /* 12?3 */ /* /* 1 */", "1";
      ("test_list_annot_1", "(x /*: [ Int ] */)",
       "(x /*: Cons(Int, X0) where X0 = nil */)");
      ("test_list_annot_2", "(x /*: [ Int* ] */)",
       "(x /*: X0 where X0 = (Cons(Int, X0)) | X1 where X1 = nil */)");
      ("test_list_annot_3", "(x /*: [ A|B ] */)",
       "(x /*: (Cons(A, X0)) | Cons(B, X1) where X0 = X1 where X1 = nil */)");
      "test_annot_singleton_int", "x /*: 1 */: x", "(x /*: 1 */: x)";
      "test_annot_singleton_true", "x /*: true */: x", "(x /*: true */: x)";
      "test_annot_singleton_false", "x /*: false */: x", "(x /*: false */: x)";
      "test_list", "[1 2 3]", "(1 :: (2 :: (3 :: nil)))";
      "test_line_comment", "x: #fooooo \n x", "(x: x)";
      "test_ite", "if e0 then e1 else e2", "if (e0) then e1 else e2";
      ("test_assert",
       "assert true; 1",
       "if (true) then 1 else (raise \"assertion failed\")");
      "test_record_1", "{ x = 1; y = 2; }", "{ x = 1; y = 2; }";
      "test_record_access", "x.y.z.a.b", "x.y.z.a.b";
      "test_record_access_dynamic", "x.${y}", "x.${y}";
      "test_record_def_dynamec", "{ ${foo} = x; }" , "{ ${foo} = x; }";
      ("test_pattern_record",
       "{ f, y ? f 3 /*: Int */ }: 1",
       "({ f, y ? (f 3) /*: Int */ }: 1)");
      "test_pattern_record_trailing_comma", "{x,}:x", "({ x }: x)";
      "test_pattern_record_open", "{x, ...}:x", "({ x, ... }: x)";
      "test_pattern_alias", "{}@x:x", "({  }@x: x)";
      ("test_record_annot",
       "(x /*: { x = Int; y =? Bool } */)",
       "(x /*: { x = Int; y =? Bool}  */)");
      ("test_record_annot_trailing_semi",
       "(x /*: { x = Int; y =? Bool; } */)",
       "(x /*: { x = Int; y =? Bool}  */)");
      ("test_record_annot_empty", "(x /*: { } */)", "(x /*: { }  */)");
      ("test_record_annot_dots", "(x /*: { ... } */)", "(x /*: { ... }  */)");
      ("test_record_annot_open",
       "(x /*: { x = Int; ... } */)",
       "(x /*: { x = Int; ... }  */)");
      "test_gradual", "(1 /*: ? */)", "(1 /*: ? */)";
      "test_nested_record_let", "let x.y = 1; in x", "let x.y = 1; in x";
      ("test_let_annot",
       "let x /*: Int */ = 1; in x",
       "let x /*: Int */ = 1; in x");
      ("test_multiple_let",
       "let x = 1; y = 2; in x",
       "let x = 1; y = 2; in x");
      "test_path", "./foo.nix", "./foo.nix";
      "test_path2", "../foo.nix", "../foo.nix";
      "test_with", "with e1; e2", "with e1; e2";
      "test_or", "x.y or z", "x.y or z";
      "test_bracket", "<foo>", "<foo>";
      "record_merge", "{} // { x = 1; }", "({ } // { x = 1; })";
      "interpol_string", "\"${foo}\"", "(foo + \"\")";
      "interpol_string2", "\"blah${foo}bar\"", "(\"blah\" + (foo + \"bar\"))";
    ]
