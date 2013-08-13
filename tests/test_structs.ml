(*
 * Copyright (c) 2013 Jeremy Yallop.
 *
 * This file is distributed under the terms of the MIT License.
 * See the file LICENSE for details.
 *)

open OUnit
open Ctypes


let testlib = Dl.(dlopen ~filename:"clib/test_functions.so" ~flags:[RTLD_NOW])


(*
  Call a function of type

     void (struct simple)

  where

     struct simple {
       int i;
       double f;
       struct simple *self;
     };
*)
let test_passing_struct () =
  let module M = struct
    type simple
    let simple : simple structure typ = structure "simple"
    let (-:) ty label = field simple label ty
    let c = int        -: "c"
    let f = double     -: "f"
    let p = ptr simple -: "p"
    let () = seal simple
      
    let accept_struct = Foreign.foreign "accept_struct" ~from:testlib
      (simple @-> returning int)

    let s = make simple

    let () = begin
      setf s c 10;
      setf s f 14.5;
      setf s p (from_voidp simple null)
    end
      
    let v = accept_struct s

    let () = assert_equal 25 v
      ~printer:string_of_int

  end in ()


(*
  Call a function of type

     struct simple(void)

  where

     struct simple {
       int i;
       double f;
       struct simple *self;
     };
*)
let test_returning_struct () =
  let module M = struct
    type simple

    let simple : simple structure typ = structure "simple"
    let (-:) ty label = field simple label ty
    let c = int        -: "c"
    let f = double     -: "f"
    let p = ptr simple -: "p"
    let () = seal simple

    let return_struct = Foreign.foreign "return_struct" ~from:testlib
      (void @-> returning simple)

    let s = return_struct ()

    let () = assert_equal 20 (getf s c)
    let () = assert_equal 35.0 (getf s f)

    let t = getf s p

    let () = assert_equal 10 !@(t |-> c)
      ~printer:string_of_int
    let () = assert_equal 12.5 !@(t |-> f)
      ~printer:string_of_float

    let () = assert_equal (to_voidp !@(t |-> p)) (to_voidp t)

  end in ()


(*
  Check that attempts to use incomplete types for struct members are rejected.
*)
let test_incomplete_struct_members () =
  let s = structure "s" in begin

    assert_raises IncompleteType
      (fun () -> field s "_" void);

    assert_raises IncompleteType
      (fun () -> field s "_" (structure "incomplete"));

    assert_raises IncompleteType
      (fun () -> field s "_" (union "incomplete"));
  end


(*
  Test reading and writing pointers to struct members.
*)
let test_pointers_to_struct_members () =
  let module M = struct
    type s

    let styp : s structure typ = structure "s"
    let (-:) ty label = field styp label ty
    let i = int     -: "i"
    let j = int     -: "j"
    let k = ptr int -: "k"
    let () = seal styp

    let s = make styp

    let () = begin
      let sp = addr s in
      sp |-> i <-@ 10;
      sp |-> j <-@ 20;
      (sp |-> k) <-@ (sp |-> i);
      assert_equal ~msg:"sp->i = 10" ~printer:string_of_int
        10 (!@(sp |-> i));
      assert_equal ~msg:"sp->j = 20" ~printer:string_of_int
        20 (!@(sp |-> j));
      assert_equal ~msg:"*sp->k = 10" ~printer:string_of_int
        10 (!@(!@(sp |-> k)));
      (sp |-> k) <-@ (sp |-> j);
      assert_equal ~msg:"*sp->k = 20" ~printer:string_of_int
        20 (!@(!@(sp |-> k)));
      sp |-> i <-@ 15;
      sp |-> j <-@ 25;
      assert_equal ~msg:"*sp->k = 25" ~printer:string_of_int
        25 (!@(!@(sp |-> k)));
      (sp |-> k) <-@ (sp |-> i);
      assert_equal ~msg:"*sp->k = 15" ~printer:string_of_int
        15 (!@(!@(sp |-> k)));
    end
  end in ()


(*
  Test structs with union members.
*)
let test_structs_with_union_members () =
  let module M = struct
    type u and s

    let complex64_eq =
      let open Complex in
      let eps = 1e-12 in
      fun { re = lre; im = lim } { re = rre; im = rim } ->
        abs_float (lre -. rre) < eps && abs_float (lim -. rim) < eps

    let utyp : u union typ = union "u"
    let (-:) ty label = field utyp label ty
    let uc = char      -: "uc"
    let ui = int       -: "ui"
    let uz = complex64 -: "uz"
    let () = seal utyp

    let u = make utyp

    let () = begin
      setf u ui 14;
      assert_equal ~msg:"u.ui = 14" ~printer:string_of_int
        14 (getf u ui);

      setf u uc 'x';
      assert_equal ~msg:"u.uc = 'x'" ~printer:(String.make 1)
        'x' (getf u uc);

      setf u uz { Complex.re = 5.55; im = -3.3 };
      assert_equal ~msg:"u.uz = 5.55 - 3.3i" ~cmp:complex64_eq
        { Complex.re = 5.55; im = -3.3 } (getf u uz);
    end

    let styp : s structure typ = structure "s"
    let (-:) ty label = field styp label ty
    let si = int  -: "si"
    let su = utyp -: "su"
    let sc = char -: "sc"
    let () = seal styp

    let s = make styp

    let () = begin
      setf s si 22;
      setf s su u;
      setf s sc 'z';

      assert_equal ~msg:"s.si = 22" ~printer:string_of_int
        22 (getf s si);
      
      assert_equal ~msg:"s.su.uc = 0.0 - 3.3i" ~cmp:complex64_eq
        { Complex.re = 5.55; im = -3.3 } (getf (getf s su) uz);

      assert_equal ~msg:"s.sc = 'z'" ~printer:(String.make 1)
        'z' (getf s sc);
    end
  end in ()


(*
  Test structs with array members.
*)
let test_structs_with_array_members () =
  let module M = struct
    type u and s

    let styp : s structure typ = structure "s"
    let (-:) ty label = field styp label ty
    let i = int            -: "i"
    let a = array 3 double -: "a"
    let c = char           -: "c"
    let () = seal styp

    let s = make styp

    let arr = Array.of_list double [3.3; 4.4; 5.5]

    let () = begin
      setf s i 22;
      setf s a arr;
      setf s c 'z';

      assert_equal ~msg:"s.i = 22" ~printer:string_of_int
        22 (getf s i);
      
      assert_equal ~msg:"s.a[0] = 3.3" ~printer:string_of_float
        3.3 (getf s a).(0);

      assert_equal ~msg:"s.a[0] = 3.3" ~printer:string_of_float
        3.3 (getf s a).(0);

      assert_equal ~msg:"s.a[1] = 4.4" ~printer:string_of_float
        4.4 (getf s a).(1);

      assert_equal ~msg:"s.a[2] = 5.5" ~printer:string_of_float
        5.5 (getf s a).(2);

      assert_raises (Invalid_argument "index out of bounds")
        (fun () -> (getf s a).(3));

      assert_equal ~msg:"s.c = 'z'" ~printer:(String.make 1)
        'z' (getf s c);

      (* References to the array member should alias the original *)
      let arr' = getf s a in
      
      arr'.(0) <- 13.3;
      arr'.(1) <- 24.4;
      arr'.(2) <- 35.5;

      assert_equal ~msg:"s.a[0] = 13.3" ~printer:string_of_float
        13.3 (getf s a).(0);

      assert_equal ~msg:"s.a[1] = 24.4" ~printer:string_of_float
        24.4 (getf s a).(1);

      assert_equal ~msg:"s.a[2] = 35.5" ~printer:string_of_float
        35.5 (getf s a).(2);
    end
  end in ()


(*
  Test that attempting to update a sealed struct is treated as an error.
*)
let test_updating_sealed_struct () =
  let styp = structure "sealed" in
  let _ = field styp "_" int in
  let () = seal styp in

  assert_raises (ModifyingSealedType "sealed")
    (fun () -> field styp "_" char)


(*
  Test that attempting to seal an empty struct is treated as an error.
*)
let test_sealing_empty_struct () =
  let empty = structure "empty" in

  assert_raises (Unsupported "struct with no fields")
    (fun () -> seal empty)


(* 
   Check that references to fields aren't garbage collected while they're
   still needed.
*)
let test_field_references_not_invalidated () =
  let module M = struct
    type s1 and s2

    (*
      struct s1 {
        struct s2 {
          int i;
        } s2;
      };
    *)
    let s1 : s1 structure typ = structure "s1"
    let () = (fun () ->
      let s2 : s2 structure typ = structure "s2" in
      let _ = field s2 "i" int in
      let () = seal s2 in
      let _ = field s1 "_" s2 in
      ()
    ) ()
    let () = begin
      Gc.major ();
      seal s1;
      assert_equal ~printer:string_of_int
        (sizeof int) (sizeof s1)
    end
  end in ()


(* 
   Test folds over struct fields.
*)
let test_folding_over_struct_fields () =
  let module M = struct
    type field_info = {
      typ : string ;
      offset : int ; 
    }

    module FieldSet = Set.Make(struct
      type t = field_info
      let compare = Pervasives.compare
    end)

    let collect_fields : 's. 's structure typ -> FieldSet.t =
      fun (type s) (s : s structure typ) ->
        fold_fields (object
          method f : 't. _ -> ('t, s structure) field -> _ =
            fun fieldset field -> 
              FieldSet.add { typ = string_of_typ (field_type field) ;
                             offset = offsetof field } fieldset
        end) FieldSet.empty s

    type s
    let s : s structure typ = structure "s"
    let (-:) ty label = field s label ty
    let a = int           -: "a"
    let b = array 3 float -: "b"
    let c = ptr void      -: "c"
    let d = ptr (ptr s)   -: "d"
    let () = seal s
      
    let expected = List.fold_right FieldSet.add
      [{offset = offsetof a; typ = string_of_typ int};
       {offset = offsetof b; typ = string_of_typ (array 3 float)};
       {offset = offsetof c; typ = string_of_typ (ptr void)};
       {offset = offsetof d; typ = string_of_typ (ptr (ptr s))}]
      FieldSet.empty

    let () = begin
      assert_equal ~cmp:FieldSet.equal expected (collect_fields s)
    end
  end in ()


let suite = "Struct tests" >:::
  ["passing struct"
    >:: test_passing_struct;
   
   "returning struct"
   >:: test_returning_struct;

   "incomplete struct members rejected"
   >:: test_incomplete_struct_members;

   "pointers to struct members"
   >:: test_pointers_to_struct_members;

   "structs with union members"
   >:: test_structs_with_union_members;

   "structs with array members"
   >:: test_structs_with_array_members;

   "updating sealed struct"
   >:: test_updating_sealed_struct;

   "sealing empty struct"
   >:: test_sealing_empty_struct;

   "field references not invalidated"
   >:: test_field_references_not_invalidated;

   "folding over struct fields"
   >:: test_folding_over_struct_fields;
  ]


let _ =
  run_test_tt_main suite
