open OUnit2

exception ParseError

let test_parse_pp_str ?(isTodo=false) input expected_output _ =
  if isTodo then todo "Not implemented yet";
  let output =
    begin
      match MParser.parse_string Parse.Parser.expr input () with
      | MParser.Success s -> Parse.Pp.pp_expr Format.str_formatter s;
      | MParser.Failed (msg, _) ->
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
      "test_arith", "x + y - z + (- a)", "+(-(+(x, y), z), -(a))";
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
      "test_list", "[1 2 3]", "Cons(1, Cons(2, Cons(3, nil)))";
    ] @
  List.map (fun (name, input, output) ->
      name >:: test_parse_pp_str ~isTodo input output)
    [
      ("test_record_pattern",
       "{ x, y, z /*: int */ }: x",
       "({ x, y, z /*: int */ }: x)");
      "test_record_expr", "{ x = 1; y = f x; }", "{ x = 1; y = (f x); }";
      ("test_list",
       "Cons (1, Cons (2, Cons (3, nil)))",
       "Cons(1, Cons(2, Cons(3, nil)))");
      ("test_list_annot",
       "(Cons (1, Cons (2, Cons (3, nil))) /*: \
        Cons(int, Cons(int, Cons(int, nil))) */)",
       "(Cons(1, Cons(2, Cons(3, nil))) /*: \
        Cons(int, Cons(int, Cons(int, nil))) */)");

      "test_line_comment", "x: #fooooo \n x", "(x: x)";
    ]
