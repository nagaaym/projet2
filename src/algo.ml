open Clause
open Formule
open Debug
open Answer
open Interaction
open Algo_base
open Conflict_analysis

type Backtrack = First | Var_depth of (int*literal) | Clause_depth of (int*clause)
(* indique comment backtracker : 
     First : inverser le premier first dispo
     Var_depth(k,l) : se rendre k level plus bas puis assigner l
     Clause_depth(k,c) : se rendre k level plus bas, puis dépiler le level k jusqu'avant que c ait deux littéraux non assignés, assigner le premier littéral de c rencontré
*)

exception End_analysis of (literal*literal list) (***)

type t = Heuristic.t -> bool -> bool -> int -> int list list -> Answer.t

let neg : literal -> literal = function (b,v) -> (not b, v)

let (@) l1 l2 = List.(rev_append (rev l1) l2)

exception Conflit of (clause*etat)




module Bind = functor(Base : Algo_base) ->
struct

  (** Bet and set *)

  (* Parie sur (b,v) puis propage. Pose la dernière tranche qui en résulte, quoiqu'il arrive *)
  let make_bet (formule:formule) (b,v) first pure_prop etat =
    let level = etat.lvl in 
    begin
      try
        formule#set_val b v lvl (* on fait le pari *)
      with 
          Empty_clause c -> (* conflit suite à pari *)
            raise (Conflit (c,{ etat with level = lvl + 1; tranches = (first,(b,v),[])::etat.tranches } )) (* on prend soin d'empiler la dernière tranche *)
    end;
    try 
      let propagation = Base.constraint_propagation pure_prop formule (b,v) etat [] in (* on propage *)
      ({ etat with level = lvl + 1; tranches = (first,(b,v),propagation)::etat.tranches }, propagation@[(b,v)]) (***) (* on renvoie l'état avec la dernière tranche ajoutée *)
    with
        Conflit_prop (c,acc) -> (* conflit dans la propagation *)
          raise (Conflit (c,{ etat with level = lvl + 1; tranches = (first,(b,v),acc)::etat.tranches } ))

  (* Compléte la dernière tranche, assigne (b,v) (ce n'est pas un pari) puis propage. c_learnt : clause apprise ayant provoqué le backtrack qui a appelé continue_bet *)
  let continue_bet (formule:formule) (b,v) ?cl pure_prop etat () = (** renommer cl ? *) (* cl : on sait de quelle clause vient l'assignation de (b,v) *)
    let lvl=etat.level in
    if lvl=0 then (* niveau 0 : tout conflit indiquerait que la formule est non sat *)
      try
        formule#set_val b v lvl; (* peut lever Empty_clause *)
        let continue_propagation = Base.constraint_propagation pure_prop formule (b,v) etat [(b,v)] in (* peut lever Conflit_prop *)
        (etat, continue_propagation)
      with 
        | Empty_clause | Conflit_prop -> raise Unsat (** Ici : le clause learning détecte que la formule est insatisfiable *)
    else    
      match etat.tranches with
        | [] -> assert false 
        | (first,pari,propagation)::q ->
            begin
              try
                formule#set_val b v ~cl:cl lvl 
              with 
                  Empty_clause c -> 
                    raise (Conflit (c,{ etat with level = lvl + 1; tranches = (first,pari,(b,v)::propagation)::q } ))
            end;
            try 
              let continue_propagation = Base.constraint_propagation pure_prop formule (b,v) etat [(b,v)] in (** pas sur pour les 5 lignes suivantes *)
              let propagation = continue_propagation@propagation in (* on poursuit l'assignation sur la dernière tranche *)
              ({ etat with level = level + 1; tranches = (first,pari,propagation)::q }, continue_propagation) 
            with
                Conflit_prop (c,acc) -> 
                  raise (Conflit (c,{ etat with level = level + 1; tranches = (first,pari,acc@propagation)::q } ))
  
  
  (** Undo *)
  
  let undo_clause formule etat c = (* on est déjà au bon niveau *)
    let aux formule (stop,acc) (b,v) =
      if (c_learnt#mem_all (not b) v) then
        match stop with
          | None -> 
              formule#reset_val v;
              (Some (not b,v),(b,v)::acc)
          | Some l -> 
              raise End_analysis (l,acc)
      else
        formule#reset_val v;
        (stop,(b,v)::acc)
  in match etat.tranches with 
    | [] -> assert false
    | (first,(b,v),propagation)::q -> (* (b,v) = pari *)
        try
          match List.fold_left aux (None,[]) propagation with
            | (None,_) -> assert false
            | (Some l,acc) ->
                if (c_learnt#mem_all (not b) v) then
                  raise End_analysis (l,acc)
                else
                  assert false
        with
          | End_analysis (l,acc) -> (l,acc)
  
  
  let undo_tranche formule etat = 
    let undo_assignation formule (_,v) = formule#reset_val v in
      match etat.tranches with (* annule la dernière tranche et la fait sauter *)
        | [] -> assert false
        | (first,pari,propagation)::q ->
            List.iter (undo_assignation formule) propagation;
            undo_assignation formule pari;
            ({ etat with level = etat.level - 1; tranches = q }, pari::(rev propagation))
  
  (*
  undo : 
    fait sauter des tranches jusqu'à atteindre la condition d'arrêt
    renvoie les listes des littéraux qu'il a fait sauter
    renvoie le prochain littéral sur lequel parier
    renvoie l'état
  *)
  let undo policy (formule:formule) etat = 
    let rec concat acc = function
      | [] -> acc
      | t::q -> concat (rev_append t acc) q in
    let rec aux policy etat acc =
      match policy with
        | First -> 
            begin
              match etat.tranches with (* annule la dernière tranche et la fait sauter *)
                | [] -> raise Unsat (** Ici le non clause learning détecte formule insatisfiable *)
                | (first,pari,propagation)::q ->
                    let (etat,prop) = undo_tranche formule etat in
                    if first then
                      (neg pari,etat,concat [] (prop::acc)) (***)
                    else
                      aux policy etat (prop::acc) (***)
            end
        | Var_depth (k,l) -> 
            if k=0 then
              (l,etat,concat [] (prop::acc)) (***)
            else
              let (etat,prop) = undo_tranche formule etat in
              aux (Var_depth(k-1,l) etat (prop::acc) (* on n'oublie pas de diminuer le level à chaque fois *) 
        | Clause_depth (k,c) ->                
            if k=0 then
              let (l,prop) = undo_clause formule etat c in
                (l,etat,concat [] (prop::acc)) (***)
            else
              let (etat,prop) = undo_tranche formule etat in
              aux (Clause_depth(k-1,c) etat (prop::acc) (* on n'oublie pas de diminuer le level à chaque fois *)                      
    in
    stats#start_timer "Backtrack (s)";
    let res = aux policy etat [] in
    stats#stop_timer "Backtrack (s)";
    res
   
  (** Algo **)

  let run (next_pari : Heuristic.t) cl interaction pure_prop n cnf = (* cl : activation du clause learning *)
    let repl = new repl (Some 1) in

    let rec process formule etat ((b,v) as lit) () = (* effectue un pari et propage le plus loin possible *)
      try
        debug#p 2 "Setting %d to %B (level : %d)" v b (etat.level+1);
        let (etat,assignations) = make_bet formule lit true pure_prop etat in (* fait un pari et propage, lève une exception si conflit créé *) (* true = first *)
          Bet_done (assignations,bet formule etat,backtrack formule etat) (* on essaye de prolonger l'assignation courante avec d'autres paris *)
      with 
        | Conflit (c,etat) ->
            stats#record "Conflits";
            debug#p 2 ~stops:true "Impossible bet : clause %d false" c#get_id;
            if interaction && repl#is_ready then
              repl#start (formule:>Formule.formule) etat c stdout;
            if (not cl) then (* pas de clause learning *)
              let (l, etat,undo_list) = undo First formule etat in (* on fait sauter la tranche, qui contient tous les derniers paris *) (** ICI : Unsat du non cl *)
                (undo_list,continue_bet formule l etat) (***) (* on essaye de retourner la plus haute pièce possible *) 
            else (* clause learning *)
              begin
                stats#start_timer "Clause learning (s)";
                let ((b,v),k,c_learnt) = conflict_analysis formule etat c in
                debug#p 2 "Learnt %a" c_learnt#print ();
                stats#stop_timer "Clause learning (s)";
                debug#p 2 "Reaching level %d to set %B %d (origin : learnt clause %d)" k b v c_learnt#get_id;
                let (_,etat,undo_list) = undo Var_depth(etat.level-k,(b,v)) formule etat in (* backtrack non chronologique <--- ici clause learning backtrack *)
                Conflit_dpll(undo_list,continue_bet formule (b,v) ~cl:c_learnt etat) (***) (* on poursuit *) (** ICI : Unsat du cl *)
              end
                
    and bet formule etat () =
      debug#p 2 "Seeking next bet";
      stats#start_timer "Decisions (s)";
      let lit = next_pari (formule:>Formule.formule) in (* choisir un littéral sur lequel parier *)
      stats#stop_timer "Decisions (s)";
      match lit with
        | None ->
            No_bet (backtrack formule etat) (* plus rien à parier = c'est gagné *)
        | Some ((b,v) as lit) ->  
            stats#record "Paris";
            debug#p 2 "Next bet : %d %B" v b;
            process formule etat lit (* on assigne (b,v) et on propage *)
    
    and backtrack formule etat clause = (***)
      let c = formule#new_clause clause in
      let (l,etat,undo_list) = undo (learn_clause formule etat c) formule etat in
        (undo_list,continue_bet formule l ~cl:c etat)
      
    in 
    try
      let (formule,prop_init) = Base.init n cnf pure_prop in
      let etat = { tranches = []; level = 0 } in
      (prop_init, bet formule etat)
    with Unsat -> Contradiction (* Le prétraitement à détecté un conflit, _ou_ Clause learning a levé cette erreur car formule unsat *) (***)

end












