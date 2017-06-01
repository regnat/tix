open OUnit2
module TA = Type_annotations
module T  = Typing.Types

exception ParseError

let get_type = Typing.Typed_ast.get_typ

let parse tokens =
  match Parse.Parser.onix Parse.Lexer.read tokens with
  | Some s -> Simple.Of_onix.expr s
  | None -> raise ParseError

let infer tenv env tokens =
  parse tokens
  |> Typing.(Typecheck.Infer.expr tenv env)

let check tenv env tokens expected_type =
  Typing.(Typecheck.Check.expr tenv env (parse tokens) expected_type)

let test_infer_expr input expected_type _ =
  let tast =
    let open Typing in
    infer Types.Environment.default Typing_env.empty (Lexing.from_string input)
  in
  assert_equal
    ~cmp:T.T.equiv
    ~printer:T.T.Print.string_of_type
    expected_type
    (get_type tast)

let test_check input expected_type _=
  let tast =
    let open Typing in
    check
      Types.Environment.default
      Typing_env.empty
      (Lexing.from_string input)
      expected_type
  in ignore tast

let test_var _ =
  let tenv = Typing.(Typing_env.(add "x" Types.Builtins.int empty)) in
  let tast =
    infer Typing.Types.Environment.default tenv (Lexing.from_string "x")
  in
  assert_equal
    Typing.Types.Builtins.int
    (get_type tast)

let test_infer_expr_fail input _ =
  try
    let _tast =
      let open Typing in
      infer
        Types.Environment.default
        Typing_env.empty
        (Lexing.from_string input)
    in
    assert_failure "type error not detected"
  with Typing.Typecheck.TypeError _ -> ()

let one_singleton = T.Builtins.interval @@ T.Intervals.singleton_of_int 1

let testsuite =
  "typecheck">:::
  [
    (* ----- Positive tests ----- *)
    "infer_var">::test_var;
    "infer_const_int">:: test_infer_expr "1" one_singleton;
    "infer_const_bool">:: test_infer_expr "true" T.Builtins.true_type;
    "infer_lambda">:: test_infer_expr "x /*: Int */: 1"
      (T.Builtins.(arrow int one_singleton));
    "infer_lambda_var">:: test_infer_expr "x /*: Int */: x"
      (T.Builtins.(arrow int int));
    "infer_apply">:: test_infer_expr "(x /*: Int */: x) 1" T.Builtins.int;
    "infer_arrow_annot">:: test_infer_expr
      "x /*: Int -> Int */: x"
      T.Builtins.(arrow (arrow int int) (arrow int int));
    "infer_let_1">:: test_infer_expr "let x = 1; in x" one_singleton;
    "infer_let_2">:: test_infer_expr "let x /*:Int*/ = 1; in x"
      T.Builtins.int;
    "infer_let_3">:: test_infer_expr "let x /*:Int*/ = 1; y = x; in y"
      T.Builtins.int;
    "infer_let_4">:: test_infer_expr "let x = 1; y = x; in y"
      T.Builtins.grad;
    "infer_let_5">:: test_infer_expr "let x = x; in x"
      T.Builtins.grad;
    "infer_shadowing">:: test_infer_expr
      "let x = true; in let x = 1; in x"
      one_singleton;
    "infer_union">:: test_infer_expr "x /*: Int | Bool */: x"
      T.Builtins.(arrow (cup int bool) (cup int bool));
    "infer_intersection">:: test_infer_expr "x /*: Int & Int */: x"
      T.Builtins.(arrow int int);

    (* ----- Negative tests ----- *)
    "infer_fail_unbound_var">:: test_infer_expr_fail "x";
    "infer_fail_apply">:: test_infer_expr_fail "1 1";
    "infer_fail_apply2">:: test_infer_expr_fail "(x /*: Bool */: x) 1";
    "infer_fail_apply3">:: test_infer_expr_fail "(x /*: Int */: x) true";

    (* ------ check ----- *)
    "check_const_one">:: test_check "1" one_singleton;
    "check_const_int">:: test_check "1" T.Builtins.int;
    "check_const_union">:: test_check "1" T.Builtins.(cup one_singleton bool)
  ]
