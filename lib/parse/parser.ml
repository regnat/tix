module Location = Common.Location

module A = Ast
module P = MParser
module T = Common.Type_annotations
module W = Location.With_loc

module StrHash = CCHashSet.Make(CCString)

let (>>=) = P.(>>=)
let (|>>) = P.(|>>)
let (<|>) = P.(<|>)
let (<?>) = P.(<??>)
let (>>)  = P.(>>)
let (<<)  = P.(<<)

type 'a t = ('a, string) MParser.t

type 'a return = ('a, string * MParser.error) result

let keywords = StrHash.of_list [
    "if"; "then"; "else";
    "let"; "in";
    "true"; "false";
    "assert";
    "rec";
    "with";
    "or";
  ]

let get_loc =
  P.get_user_state >>= fun file_name ->
  P.get_pos |>> fun (_, lnum, cnum) ->
  Location.{ file_name; lnum; cnum; }

let add_loc x =
  get_loc >>= fun loc ->
  x |>> fun x ->
  W.mk loc x

(** {2 Some utility functions } *)
let any x = P.choice @@ List.map P.attempt x

let block_comment =
  (P.attempt (P.string "/*" << P.not_followed_by (P.char ':') "colon")) >>
  P.skip_many_chars_until P.any_char_or_nl (P.char '*' << P.char '/')

let line_comment = P.char '#' << P.not_followed_by (P.string "::") ""
  >> P.skip_many_until P.any_char P.newline

let comment = P.choice [ block_comment; line_comment; ] <?> "comment"

let one_space = (P.skip P.space <|> comment <?> "whitespace")
let space = P.skip_many one_space

let keyword k = P.string k <<
                P.not_followed_by P.alphanum "not a keyword" << space

let alphanum_ = P.alphanum <|> P.any_of "_-'"
let letter_ = P.letter <|> P.char '_'

let isolated_dot =
  P.char '.' << P.not_followed_by (P.any_of "./") "begin of path"

let ident =
  P.attempt @@ (letter_ >>= fun c0 ->
   P.many_chars alphanum_ << space >>= fun end_name ->
   let name = (CCString.of_char c0) ^ end_name in
   if StrHash.mem keywords name then
     P.zero
   else
     P.return name)
  <?> "ident"

let uri =
  let scheme =
    P.letter >>= fun c0 ->
    P.many_chars (P.alphanum <|> P.any_of "+-.") |>> fun end_scheme ->
    (CCString.of_char c0) ^ end_scheme
  and uriEnd = P.many1_chars (P.alphanum <|> P.any_of "%/?:@&=+$,-_.!~*'")
  in
  P.attempt (scheme << P.char ':') >>= fun s ->
  uriEnd << space |>> fun e ->
  s ^ ":" ^ e

let int = P.many1_chars P.digit << space |>> int_of_string

let parens x = P.char '(' >> space >> x << P.char ')' << space

let bool = P.choice
    [keyword "true" >> P.return true;
     keyword "false" >> P.return false]
           << space
           <?> "boolean"

let schar escape delim =
  (escape >> P.any_char_or_nl)
  <|>
  (P.not_followed_by delim "end of string" >> P.any_char_or_nl)

let antiQuot expr =
  (P.attempt @@ P.string "${" >> expr) << P.char '}'
  (* Don't skip spaces because it is used in strings *)
  <?> "anti quotation"

let string (expr : (A.expr, string) P.t) =
  let antiQuot =
    add_loc (antiQuot expr) |>> fun e -> `Expr e
  and plainChar escape delim =
    (add_loc @@ schar escape delim)
    |>> fun c -> `Char c
  and flattenString loc l =
    let rec aux loc cur_buf_opt lst =
      match (cur_buf_opt, lst) with
      | Some b, `Char { W.description = c; _ }::tl ->
        Buffer.add_char b c;
        aux loc (Some b) tl
      | Some b, (`Expr e_wl::_ as l) ->
        let current_string = Buffer.contents b in
        Buffer.clear b;
        let e = aux loc None l in
        W.mk (W.loc e_wl)
        @@ A.Ebinop (A.Oplus,
                  W.mk loc
                  @@ A.Econstant (A.Cstring current_string),
                  e)
      | None, `Char { W.description = c; location = loc; }::tl ->
        let b = Buffer.create 127 in
        Buffer.add_char b c;
        aux loc (Some b) tl
      | None, `Expr e_wl::tl ->
        let e = W.description e_wl in
        W.mk (W.loc e_wl) @@ A.Ebinop (A.Oplus, e, (aux loc None tl))
      | None, [] -> W.mk loc @@ A.Econstant (A.Cstring "")
      | Some b, [] -> W.mk loc @@ A.Econstant (A.Cstring (Buffer.contents b))
    in aux loc None l
  in
  let str escape delim = delim >>
    get_loc >>= fun loc ->
    P.many (antiQuot <|> plainChar escape delim) << delim << space |>> flattenString loc
  in
  let simple_string =
    str (P.char '\\') (P.char '"')
    <?> "simple string"
  and indented_string =
    str
      (P.attempt (P.string "''" << P.followed_by (P.char '$') "dollar escape"))
      (P.string "''")
    <?> "indented string"
  in
  simple_string <|> indented_string

let litteral_string =
  P.char '"' >> P.many_chars_until (schar (P.char '\\') (P.char '"')) (P.char '"') << space

let litteral_path =
  ((P.attempt @@ P.string "./" <|> P.string "../") >>= fun prefix ->
   P.many_chars (P.choice [ P.alphanum; P.any_of "-/_.+" ]) << space |>> fun path ->
   prefix ^ path)
  <?> "Path"

let bracketed_path =
  (P.char '<' >>
   P.many_chars (P.choice [ P.alphanum; P.any_of "-/_." ]) <<
   P.char '>' << space |>> fun content ->
   content)
  <?> "Bracketed path"

let infix_ops =
  let infix sym f assoc = P.Infix (
      (get_loc >>= fun loc ->
       P.skip_string sym >> space >>
       P.return (fun e1 e2 ->
           W.mk loc (f e1 e2))),
      assoc)
  and prefix sym f = P.Prefix (
      get_loc >>= fun loc ->
      P.skip_string sym >> space >>
      P.return (fun e -> W.mk loc (f e)))
  in
  [
    [ prefix "-" (fun e -> A.Emonop (A.Oneg, e));
      prefix "!" (fun e -> A.Emonop (A.Onot, e));
    ];
    [
      infix "==" (fun e1 e2 -> A.Ebinop (A.Oeq, e1, e2)) P.Assoc_left;
      infix "!=" (fun e1 e2 -> A.Ebinop (A.OnonEq, e1, e2)) P.Assoc_left;
      infix "+" (fun e1 e2 -> A.Ebinop (A.Oplus, e1, e2)) P.Assoc_left;
      infix "-" (fun e1 e2 -> A.Ebinop (A.Ominus, e1, e2)) P.Assoc_left;
      infix "//" (fun e1 e2 -> A.Ebinop (A.Omerge, e1, e2)) P.Assoc_left;
      infix "++" (fun e1 e2 -> A.Ebinop (A.Oconcat, e1, e2)) P.Assoc_left;
    ];
    [
      infix "&&" (fun e1 e2 -> A.Ebinop (A.Oand, e1, e2)) P.Assoc_left;
      infix "||" (fun e1 e2 -> A.Ebinop (A.Oor, e1, e2)) P.Assoc_left;
      infix "->" (fun e1 e2 -> A.Ebinop (A.Oimplies, e1, e2)) P.Assoc_left;
    ];
  ]

(** {2 Begining of the parser } *)

(** {3 Type annotations} *)

let typ_op =
  let module I = T.Infix_constructors in
  let infix sym op assoc = P.Infix (
      (get_loc >>= fun loc -> P.skip_string sym >> space >>
       P.return (fun t1 t2 ->
           W.mk loc (T.Infix (op, t1, t2)))),
      assoc)
  in
  [
    [ infix "&" I.And P.Assoc_left ];
    [ infix "|" I.Or P.Assoc_left ];
    [ infix "\\" I.Diff P.Assoc_left ];
    [ infix "->" I.Arrow P.Assoc_right ];
  ]


let typ_regex_postfix_op =
  get_loc >>= fun loc ->
  let mkloc = W.mk loc in
  P.choice [
    P.char '*' >> space >> P.return (fun r -> mkloc @@ Regex_list.Star r);
    P.char '+' >> space >> P.return (fun r -> mkloc @@ Regex_list.Plus r);
    P.char '?' >> space >> P.return (fun r -> mkloc @@ Regex_list.Maybe r);
  ]

let typ_int =
  int |>> fun nb ->
  T.(Singleton (Singleton.Int nb))

let typ_bool =
  bool |>> fun b ->
  T.(Singleton (Singleton.Bool b))

let typ_string =
  litteral_string |>> fun s ->
  T.(Singleton (Singleton.String s))

let typ_path =
  litteral_path |>> fun s ->
  T.(Singleton (Singleton.Path s))

let typ_ident i = i |> add_loc (
    (ident |>> fun t -> T.Var t)
    <|>
    (P.char '?' >> space >> P.return T.Gradual))
and typ_singleton i = i |> add_loc
  @@ P.choice [typ_int; typ_bool; typ_string; typ_path ]

let rec typ i =
  i |> (
    typ_simple >>= fun t ->
    P.many_fold_left
      (fun accu_ty -> W.map (fun c -> T.TyBind (c, accu_ty)))
      t
      where_clause)

and where_clause i =
  i |> add_loc (
    keyword "where" >>
    P.sep_by typ_binding (keyword "and")
  )

and typ_binding i =
  i |> (
    ident >>= fun name ->
    P.char '=' >> space >>
    typ |>> fun t ->
    (name, t)
  )

and typ_simple i = i |> (P.expression typ_op
                           (P.choice [typ_list; typ_record; typ_atom;])
                      <?> "type")

and typ_atom i = i |> P.choice [ typ_singleton; typ_ident; parens typ]

and typ_regex i =
  i |> (
    any [typ_regex_alt; typ_regex_concat; ]
    <?> "type regex")

and typ_regex_alt i =
  i |> add_loc (
    typ_regex_concat >>= fun t1 ->
    P.char '|' >> space >>
    typ_regex |>> fun t2 ->
    Regex_list.Or (t1, t2))

and typ_regex_postfix i =
  i |> (
    typ_regex_atom >>= fun r0 ->
    P.many typ_regex_postfix_op |>> fun ops ->
    List.fold_left (fun r op -> op r) r0 ops
  )

and typ_regex_atom i =
  i |> (
    parens typ_regex
    <|>
    (add_loc (typ_atom |>> fun t -> Regex_list.Type t)))

and typ_regex_concat i =
  i |> (
    get_loc >>= fun loc ->
    typ_regex_postfix >>= fun r0 ->
    P.many typ_regex_postfix |>> fun tl ->
    List.fold_left (fun accu r ->
        W.mk loc (Regex_list.Concat (accu, r)))
      r0
      tl
  )

and typ_list i =
  i |> (
    P.char '[' >> space >> typ_regex << P.char ']' << space |>>
    Regex_list.to_type)

and typ_record i =
  i |> add_loc ((
      P.char '{' >> space >> typ_record_fields << P.char '}' << space
      |>> fun (fields, is_open) ->
      T.Record (fields, is_open))
      <?> "type record")

and typ_record_fields i =
  i |> P.choice [
    (typ_record_field << P.optional (P.char ';') << space >>= fun field ->
     typ_record_fields |>> fun (fields, is_open) ->
     (field :: fields, is_open));
    (P.string "..." >> space >> P.return ([], true));
    (P.return ([], false));
  ]

and typ_record_field i =
  i |> (
    ident >>= fun name ->
    (P.char '=' >> P.option (P.char '?') << space |>> CCOpt.is_some)
    >>= fun is_optional ->
    typ |>> fun t -> (name, (is_optional, t))
  )

let type_annot = (P.string "/*:" >> space >> typ << P.string "*/" << space)
                 <?> "type annotation"

(** {3 Expressions} *)

let expr_int = add_loc (
    int |>> fun nb ->
    A.Econstant (A.Cint nb)
  )

let expr_bool = add_loc (
    bool |>> fun b ->
    A.Econstant (A.Cbool b)
  )

let expr_path = add_loc (
    litteral_path |>> fun s ->
    A.Econstant (A.Cpath s)
  )

let expr_uri = add_loc (
    uri |>> fun s ->
    A.Econstant (A.Cstring s)
  )

let expr_bracket = add_loc (
    bracketed_path |>> fun brack ->
    A.Econstant (A.Cbracketed brack)
  )

let expr_ident = add_loc (
    ident |>> fun id ->
    A.Evar id
  )

let pattern_var =
  ident >>= fun id ->
  P.option (P.attempt type_annot) |>> fun annot ->
  (id, annot)

let pattern_ident = add_loc (
    pattern_var |>> fun (id, annot) ->
    A.Pvar (id, annot)
  )

and expr_const =
  (P.choice [expr_int; expr_bool; expr_path; expr_uri; expr_bracket])
  <?> "constant"

let rec expr i =
  i |> (
    P.choice [
      expr_pragma;
      expr_let;
      expr_if;
      expr_assert;
      expr_with;
      expr_lambda;
      P.attempt expr_infix;
      expr_apply_or_member;
    ]
  )

and expr_pragma i =
  i |> (add_loc (
      P.string "#::" >>
      space >>
      keyword "WARN" >>
      P.many1 warning_annot >>= fun warnings ->
      P.skip_many P.blank >> P.newline >> space >>
      expr |>> fun e ->
      A.Epragma (Pragma.Warnings warnings, e))
      <?> "Pragma"
    )

and warning_annot i =
  i |> (
    P.any_of "+-" >>= fun sign_char ->
    let sign = if sign_char = '+' then Pragma.Plus else Pragma.Minus in
    ident >>= fun name ->
    match Pragma.Warning.read name with
    | Some w -> P.return (sign, w)
    | None -> P.fail "Invalid warning name")

and expr_with i =
  i |> add_loc (
    keyword "with" >>
    expr << P.char ';' << space >>= fun e1 ->
    expr |>> fun e2 ->
    A.Ewith (e1, e2))

and expr_assert i =
  i |> add_loc (
    get_loc >>= fun loc ->
    keyword "assert" >>
    expr >>= fun assertion ->
    P.char ';' >> space >>
    expr |>> fun k ->
    A.Eite ( assertion, k, W.mk loc @@ A.EfunApp (
        W.mk loc (A.Evar "raise"),
        W.mk loc (A.Econstant (A.Cstring "assertion failed")))))

and expr_infix i =
  i |> (P.expression infix_ops expr_apply_or_member)

and expr_infix_member i =
  i |> add_loc (
    expr_apply >>= fun e ->
    P.char '?' >> space >>
    ap |>> fun ap ->
    A.EtestMember (e, ap)
  )

and expr_apply_or_member i =
  i |> (
    P.attempt expr_infix_member
    <|> expr_apply
  )

and expr_if i =
  i |> (add_loc
          (keyword "if" >>
           expr >>= fun e_if ->
           keyword "then" >>
           expr >>= fun e_then ->
           keyword "else" >>
           expr |>> fun e_else ->
           A.Eite (e_if, e_then, e_else)
          )
        <?> "if-then-else")

and expr_atom i =
  i |> (
    P.choice [
      expr_record; expr_list;
      expr_string; expr_const; expr_ident;
      expr_paren
        ]
    <?> "atomic expression"
  )

and expr_string i = string expr i

and expr_record i =
  i|> add_loc (
    P.option (P.attempt @@ keyword "rec") >>= fun maybe_isrec ->
    let recursive = CCOpt.is_some maybe_isrec in
    expr_record_nonrec |>> fun fields ->
    A.(Erecord { recursive; fields }))

and expr_record_nonrec i =
  i |> (
    P.char '{' >> space >>
    P.many (expr_record_field <|> expr_inherit)
    << P.char '}' << space
    <?> "record"
  )

and expr_record_field i =
  i |> add_loc (P.attempt (
      ap_pattern >>= fun ap ->
      P.char '=' >> space >>
      expr << P.char ';' << space |>> fun value ->
      A.Fdef (ap, value))
      <?> "record field or binding"
    )

and expr_inherit i =
    i |> add_loc (P.attempt (
    keyword "inherit" >>
    P.option (P.char '(' >> space >> expr << P.char ')' << space) >>= fun base_def ->
    P.sep_by1 (add_loc @@ ident) space << P.char ';' << space |>> fun fields ->
    A.Finherit (base_def, fields)
  )
  )

and expr_list i =
  i |> (
    get_loc >>= fun loc ->
    P.char '[' >> space >>
    P.many_rev_fold_left
      (fun accu elt -> W.mk loc (A.Ebinop (A.Ocons, elt, accu)))
      (W.mk loc @@ A.Evar "nil")
      expr_select
    << P.char ']' << space
  )

and expr_paren i =
  i |> (
    get_loc >>= fun loc ->
    parens (
      expr >>= fun e ->
      P.option type_annot |>> function
      | None -> e
      | Some t -> W.mk loc @@ A.EtyAnnot (e, t)
    ))

and expr_lambda i =
  i |> (add_loc (
      P.not_followed_by uri "uri" >>
      P.attempt (pattern << P.char ':') >>= fun pat -> space >>
      expr |>> fun body ->
      A.Elambda (pat, body)
    )
        <?> "lambda")

and expr_let i =
  i |> (add_loc (
      keyword "let" >>
      P.many1 (expr_inherit <|> expr_record_field) >>= fun b ->
      keyword "in" >>
      expr |>> fun e ->
      A.Elet (b, e)
    )
        <?> "let binding")

and pattern i = i |> (P.choice [pattern_ident; pattern_complex] <?> "pattern")

and pattern_complex i =
  i |> add_loc (
    (pattern_record >>= fun record ->
     P.option (P.char '@' >> space >> ident) |>> fun alias_opt ->
     A.Pnontrivial (record, alias_opt));
  )


and pattern_record_field i =
  i |> ((
      ident >>= fun field_name ->
      P.option (P.char '?' >> space >> expr) >>= fun default_value ->
      P.option type_annot |>> fun type_annot ->
      A.{ field_name; default_value; type_annot })
      <?> "pattern record field")

and pattern_inside i =
  i |> P.choice [
    (pattern_record_field << P.optional (P.char ',') << space >>= fun field ->
     pattern_inside |>> fun (A.NPrecord (fields, open_flag)) ->
     A.NPrecord (field::fields, open_flag));

    (P.string "..." >> space >> P.return @@ A.NPrecord ([], A.Open));

    P.return @@ A.NPrecord ([], A.Closed);
  ]

and pattern_record i =
  i |> ((
      P.char '{' >> space >>
      pattern_inside << P.char '}' << space)
      <?> "record pattern")

and expr_apply i =
  i |>
  (get_loc >>= fun loc ->
   expr_select >>= fun e0 ->
   P.many expr_select |>>
   List.fold_left (fun accu e -> W.mk loc (A.EfunApp (accu, e))) e0)

and expr_select i =
  i |> (add_loc (
          P.attempt (expr_atom << isolated_dot) >>= fun e ->
          space >>
          ap >>= fun a ->
          P.option (P.attempt expr_select_guard) |>> fun guard ->
          A.Eaccess (e, a, guard))
        <|>
        expr_atom
       )

and ap i = i |> P.sep_by1 ap_field (P.attempt isolated_dot >> space)

and expr_select_guard i = i |> ( keyword "or" >> expr)

and ap_pattern i =
  i |> (
    ap >>= fun access_path ->
    P.option (P.attempt type_annot) |>> fun annot ->
    (access_path, annot))

and ap_field i =
  i |> add_loc (
    (antiQuot expr << space |>> fun e -> A.AFexpr e)
    <|>
    (expr_string |>> fun e -> A.AFexpr e)
    <|>
    (ident |>> fun f_name -> A.AFidentifier f_name)
  )

let expr =
  space >> expr << P.eof

let typ =
  space >> typ << P.eof

let mpresult_to_result = function
  | MParser.Success x -> Ok x
  | MParser.Failed (msg, e) -> Error (msg, e)

let parse_string parser str =
  MParser.parse_string parser str "-"
  |> mpresult_to_result
