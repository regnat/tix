open OUnit2

exception ParseError


let test_parse_pp_str ?(isTodo=false) input expected_output _ =
  if isTodo then todo "Not implemented yet";
  let output =
    Onix_parser.onix Onix_lexer.read (Lexing.from_string input)
    |> Nl_of_onix.expr
    |> fun s -> Nl_pp.pp_expr Format.str_formatter s;
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
      "test_app", "x y", "x y";
      "test_lambda_app", "(x: y) z", "(x: y) z";
      "test_app_lambda", "x: y z", "(x: y z)";
      "test_Y_comb", "(x: x x) (x: x x)", "(x: x x) (x: x x)";
      "test_annot", "(x /*: int */)", "(x /*: int */)";
      "test_annot_arrow", "(x /*: int -> int */)", "(x /*: (int) -> int */)";
      "test_list", "Cons (1, Cons (2, Cons (3, nil)))", "Cons(1, Cons(2, Cons(3, nil)))";
      "test_list_sugar", "[1 2 3]", "Cons(1, Cons(2, Cons(3, nil)))";
      "test_annot_lambda", "x: /*: int -> int */ x", "(x: /*: (int) -> int */ x)";
    ] @
  [
  ]
