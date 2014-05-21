open Clause

type atom = string



let parse_atom s = Formula_tree.Atom s

let print_atom p s = Printf.fprintf p "%s" s

(* Théorie *)

type etat = unit

exception Conflit_smt of (literal list*etat)
    

let normalize formula = formula
  
let init _ = () 
  
let propagate _ _ etat = etat
  
let backtrack _ _ etat = etat

let print_answer reduc _ values p =
  reduc#iter
    (fun s v -> 
      match values#find v with
        | None -> assert false
        | Some b -> if b then Printf.fprintf p "v %s\n" s else Printf.fprintf p "v -%s\n" s)
  
let pure_prop = true
