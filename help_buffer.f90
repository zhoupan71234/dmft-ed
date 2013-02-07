  allocate(help_buffer(62))
  help_buffer=([&
       'NAME',&
       '  full_ed',&
       '',&
       'DESCRIPTION',&
       '  This code solve an impurity problem by mean of complete Exact Diagonalization.',&
       '  For any given bath+impurity hamiltionian, the code evaluate the spectrum of the',&
       '  problem, the impurity Green`s functions, some observables and optionally the ',&
       '  spin susceptibility.',&
       '  The bath hamiltionian is generated from scratch the first call to the main routine.',&
       '  If the file `Hfile` is found, the hamiltonian is read from it. ',&
       '  Alternativel, if `Hfile` is not found but `Dfile` exists, the bath hybridization Delta function',&
       '  is read from it and the hamiltionian is generated thru a conjgate gradient fit, similar',&
       '  to that used to implement the self-consistency condition.',&
       '  ',&
       '  The self-consistency (the cg-fit) must be provided by the user (reverse communication) as well as',&
       '  the calculation of the Delta function. The former can be performed using the routines supplied with ',&
       '  this code. A different user-defined method can also be used. ',&
       '  ',&
       '  (to be finished)',&
       '  ',&
       '  ',&
       'OPTIONS',&
       'Ns   [5]    -- Number of bath sites per spin.',&
       'Norb [1]    -- Number of local orbitals.',&
       'Nspin [1]   -- Number of spin channels (max=2).',&
       'nloop [50]  -- Max. number of iterations.',&
       'd [1.0]     -- Half-bandwidth.',&
       'beta [50.0] -- Inverse temperature.',&
       'xmu [0.0]   -- Chemical potential.',&
       'u [2.0]     -- Local interaction (Hubbard term).',&
       'v [0.0]     -- N.N. interaction.',&
       'ts [0.5]    -- N.N. Hopping parameter.',&
       'tsp [0.0]   -- N.N.N. Hopping parameter.',&
       'tpd [0.0]   -- Local hybridization..',&
       'tpp [0.0]   -- N.N. diagonal hopping.',&
       'ep0 [0.0]   -- Impurity electronic level 1.',&
       'ed0 [0.0]   -- Impurity electronic level 2.',&
       'NL [2048]   -- Number of Matsubara frequencies.',&
       'Nw [1024]   -- Number of real frequencies.',&
       'Ltau [512]  -- Number of imaginary time points.',&
       'Nfit [2048] -- Number of fitted frequncies.',&
       'eps_error=[1.d-4] -- Convergence tolerance',&
       'Nsuccess =[2]     -- Number of successive convergence treshold',&
       'chiflag [.false.] -- Evaluation flag for spin susceptibility.',&
       'eps [0.035]       -- Broadening constant.',&
       'weigth [0.8]      -- Mixing weight (mispelled).',&
       'nread [0.0]       -- Target density for chemical potential search.',&
       'nerror [1.d-4]    -- Tolerance in chemical potential search.',&
       'ndelta [0.10]     -- Starting delta for chemical potential search.',&
       'wmin [-4.0]       -- Lower bound frequency interval.',&
       'wmax [4.0]        -- Upper bound frequency interval.',&
       'heff [0.0]        -- Symmetry Breaking field.',&
       'Nx [100]          -- Number of points on a lattice mesh (x-axis).',&
       'Ny [100]          -- Number of points on a lattice mesh (y-axis).',&
       'cutoff [1.e-9]    -- Cutoff parameter for the spectrum contributing to GF calculation.',&
       'Hfile [Hamiltonian.restart] -- Store bath hamiltonian .',&
       'Ofile [Observables.data]    -- Store observables.',&
       'Dfile [Delta.restart]       -- Store delta function.',&
       'GMfile [gfMimp.data]   -- Store GF Matsubara.',&
       'GRfile [gfRimp.data]   -- Store GF Real-axis.',&
       'CTfile [chiTimp.data]  -- Store Chi Im. time.',&
       '  '])
  call parse_cmd_help(help_buffer)
