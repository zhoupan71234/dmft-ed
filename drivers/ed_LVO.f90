program ed_LVO_hetero
  USE DMFT_ED
  USE SCIFOR
  USE DMFT_TOOLS
  USE MPI
  implicit none
  !
  !############################################################################
  !#                                                                          #
  !#                      THIS CODE IS MPI COMPILED ONLY                      #
  !#                                                                          #
  !############################################################################
  !
  !
  !########################   VARIABLEs DECLARATION   #########################
  !
  integer                                             :: iloop
  integer                                             :: i,j,io,jo,ndx
  integer                                             :: iorb,jorb
  integer                                             :: ispin,jspin
  integer                                             :: ilat,jlat
  integer                                             :: ifreq,Lfreq
  integer                                             :: ilayer,Nlayer
  integer                                             :: NlNsNo,NsNo
  logical                                             :: converged
  !Parsed:
  character(len=60)                                   :: finput
  integer                                             :: Nk,Nlat,Nkpath
  real(8)                                             :: wmixing
  logical                                             :: computeG0loc
  character(len=32)                                   :: geometry,z_symmetry,gauge
  logical                                             :: bulk_magsym,diaglocalpbm
  integer                                             :: Nr,Nt,Nphotons
  logical                                             :: Efield
  real(8)                                             :: tmax
  !Mpi:
  integer                                             :: comm,rank,ier,siz
  logical                                             :: master
  !Bath:
  integer                                             :: Nb
  real(8)   ,allocatable,dimension(:,:)               :: Bath
  real(8)   ,allocatable,dimension(:)                 :: Bath_single
  !Hamiltoninas:
  integer                                             :: ik,Lk
  complex(8),allocatable,dimension(:,:,:)             :: Hk
  complex(8),allocatable,dimension(:,:)               :: Hloc_lso
  complex(8),allocatable,dimension(:,:,:,:,:)         :: Hloc_nnn
  real(8)   ,allocatable,dimension(:)                 :: Wtk
  !local dmft fields:
  complex(8),allocatable,dimension(:,:,:,:,:,:)       :: Smats,Sreal
  complex(8),allocatable,dimension(:,:,:,:,:,:)       :: Gmats,Greal
  complex(8),allocatable,dimension(:,:,:,:,:,:)       :: field,field_old
  !Irreducible dmft fields:
  complex(8),allocatable,dimension(:,:,:,:,:,:)       :: Smats_hetero,Sreal_hetero
  complex(8),allocatable,dimension(:,:,:,:,:)         :: Smats_single,Sreal_single
  !meshes:
  real(8)                                             :: dw
  real(8)   ,allocatable,dimension(:)                 :: wr,wm
  !convergence test:
  complex(8),allocatable,dimension(:)                 :: conv_funct
  !custom variables for chempot search:
  logical                                             :: converged_n
  integer                                             :: conv_n_loop=0
  real(8)                                             :: sumdens,xmu_old
  real(8)   ,allocatable,dimension(:,:)               :: orb_dens_lat,orb_mag_lat
  real(8)   ,allocatable,dimension(:)                 :: orb_dens_single,orb_mag_single
  logical                                             :: look4n=.true.
  !custom variables misc:
  logical                                             :: lattice_flag=.true.
  character(len=60)                                   :: HRfile
  complex(8),allocatable,dimension(:,:)               :: U,Udag
  complex(8),allocatable,dimension(:,:)               :: zeta
  complex(8),allocatable,dimension(:,:)               :: Nmatrix_so
  complex(8),allocatable,dimension(:,:,:,:,:)         :: Nmatrix_nn
  complex(8),allocatable,dimension(:,:,:,:,:,:)       :: Gloc
  !fake flags
  logical                                             :: fake_potential=.false.

  !##########################   MPI INITIALIZATION   ##########################
  !
  call init_MPI()
  comm = MPI_COMM_WORLD
  call StartMsg_MPI(comm)
  master = get_Master_MPI(comm)
  siz    = get_size_MPI(comm)
  rank   = get_rank_MPI(comm)
  if(master)then
     write(LOGfile,*) " size",siz
     write(LOGfile,*) " rank",rank
  endif
  !
  !
  !##########################    VARIABLE PARSING    ##########################
  !
  !
  call parse_cmd_variable(finput           ,"FINPUT",              default='inputED_LVO.in')
  call parse_input_variable(nk             ,"NK"          ,finput, default=10              )
  call parse_input_variable(NLAT           ,"NLAT"        ,finput, default=4               )
  call parse_input_variable(nkpath         ,"NKPATH"      ,finput, default=20              )
  call parse_input_variable(wmixing        ,"WMIXING"     ,finput, default=0.5d0           )
  call parse_input_variable(computeG0loc   ,"COMPUTEG0loc",finput, default=.false.         )
  call parse_input_variable(geometry       ,"GEOMETRY"    ,finput, default="bulk"          )
  call parse_input_variable(z_symmetry     ,"ZSYMMETRY"   ,finput, default="FERRO"         )
  call parse_input_variable(bulk_magsym    ,"BULKMAGSYM"  ,finput, default=.false.         )
  call parse_input_variable(diaglocalpbm   ,"DIAGLOCAL"   ,finput, default=.false.         )
  call parse_input_variable(Efield         ,"EFIELD"      ,finput, default=.false.         )
  call parse_input_variable(Nr             ,"NR"          ,finput, default=10              )
  call parse_input_variable(Nt             ,"NT"          ,finput, default=100             )
  call parse_input_variable(tmax           ,"TMAX"        ,finput, default=5.d0            )
  call parse_input_variable(gauge          ,"GAUGE"       ,finput, default="E"             )
  call parse_input_variable(Nphotons       ,"NPHOTONS"    ,finput, default=5               )
  !
  call ed_read_input(trim(finput),comm)
  !
  !Add DMFT CTRL Variables:
  call add_ctrl_var(Norb    ,"norb"    )
  call add_ctrl_var(Nspin   ,"nspin"   )
  call add_ctrl_var(Nlat    ,"nlat"    )
  call add_ctrl_var(beta    ,"beta"    )
  call add_ctrl_var(Lfit    ,"Lfit"    )
  call add_ctrl_var(xmu     ,"xmu"     )
  call add_ctrl_var(wini    ,'wini'    )
  call add_ctrl_var(wfin    ,'wfin'    )
  call add_ctrl_var(eps     ,"eps"     )
  call add_ctrl_var(ed_para ,"ed_para" )
  call add_ctrl_var(cg_Ftol ,"cg_Ftol" )
  call add_ctrl_var(cg_Niter,"cg_Niter")
  !
  geometry=reg(geometry)
  z_symmetry=reg(z_symmetry)
  gauge=reg(gauge)
  if (geometry=="bulk".and.ed_para)    lattice_flag=.false.
  if (geometry=="bulk".and.bulk_magsym)lattice_flag=.false.
  if (geometry=="bulk".and.Nlat/=4) stop
  if (bath_type=="replica") stop
  if(Efield.and.(nloop.ne.-1))stop "  Time-dependent Hk and DMFT not compatible"
  !
  Nlayer=Nlat/2
  NlNsNo=Nlat*Nspin*Norb
  NsNo=Nspin*Norb
  !
  !
  !##########################       ALLOCATION       ##########################
  !
  !
  if(nloop.gt.-1)then
     allocate(Smats(Nlat,Nspin,Nspin,Norb,Norb,Lmats));   Smats=zero
     allocate(Gmats(Nlat,Nspin,Nspin,Norb,Norb,Lmats));   Gmats=zero
     allocate(Sreal(Nlat,Nspin,Nspin,Norb,Norb,Lreal));   Sreal=zero
     allocate(Greal(Nlat,Nspin,Nspin,Norb,Norb,Lreal));   Greal=zero
     allocate(field(Nlat,Nspin,Nspin,Norb,Norb,Lmats));   field=zero
  endif
  !
  allocate(wr(Lreal));wr=0.0d0;      wr=linspace(wini,wfin,Lreal,mesh=dw)
  allocate(wm(Lmats));wm=0.0d0;      wm = pi/beta*real(2*arange(1,Lmats)-1,8)
  !
  Lfit=min(int((Uloc(1)+3.)*(beta/pi))+100,Lmats)
  if(master)write(LOGfile,'(a12,I6,2(a12,F10.3))')"Lfit:",Lfit,"iwmax:",(pi/beta)*(2*Lfit-1),"U+2D:",Uloc(1)+3.
  !
  !
  !##########################        BUILD Hk        ##########################
  !
  !
  if(geometry=="bulk")  HRfile=reg("LVO_hr_bulk.dat")  
  if(geometry=="hetero")HRfile=reg("LVO_hr_hete.dat")
  !
  call read_myhk(HRfile,"Hk.dat","Hloc","Kpoints.dat",diaglocalpbm,Efield)
  !
  if(nloop==-1) stop "  STOP. Calc of Ho"
  !
  if(diaglocalpbm)then
     write(LOGfile,*) " --- LOCAL PROBLEM SOLVED IN THE DIAGONAL BASIS --- "
  else
     write(LOGfile,*) " --- LOCAL PROBLEM SOLVED IN THE NON-DIAGONAL BASIS --- "
     write(LOGfile,*) " --- Warning: mess shall rise in impSigma symmetrization"
  endif
  !
  !
  !##########################  READ EXISITING impS   ##########################
  !
  !
  if(nloop==0)then
     if (lattice_flag)then
        allocate(Smats_hetero(Nlayer,Nspin,Nspin,Norb,Norb,Lmats));Smats_hetero=zero
        allocate(Sreal_hetero(Nlayer,Nspin,Nspin,Norb,Norb,Lreal));Sreal_hetero=zero
        call ed_read_impSigma_lattice(Nlayer)
        call sigma_symmetrization()
        deallocate(Smats_hetero,Sreal_hetero)
     else
        allocate(Smats_single(Nspin,Nspin,Norb,Norb,Lmats));Smats_single=zero
        allocate(Sreal_single(Nspin,Nspin,Norb,Norb,Lreal));Sreal_single=zero
        call ed_read_impSigma_single()
        call sigma_symmetrization()
        deallocate(Smats_single,Sreal_single)
     endif
  endif
  !
  !
  !##########################          BATH          ##########################
  !
  !
  Nb=get_bath_dimension()
  if(master)write(LOGfile,*)"   Bath_size: ",Nb," layers: ",Nlayer
  allocate(Bath(Nlayer,Nb));    Bath=0.0d0
  allocate(Bath_single(Nb));    Bath_single=0.0d0
  !
  !
  !##########################      INIT SOLVER       ##########################
  !
  !
  if(nloop.gt.0)then
     if (lattice_flag)then
        call ed_init_solver(Comm,Bath,Hloc_nnn(1:Nlat:2,:,:,:,:))
     else
        call ed_init_solver(Comm,Bath_single,Hloc_nnn(1,:,:,:,:))
     endif
  endif
  !
  !
  !##########################          DMFT          ##########################
  !
  !
  iloop=0 ; converged=.false.
  do while(.not.converged.AND.iloop<nloop)
     iloop=iloop+1
     if(master)call start_loop(iloop,nloop,"DMFT-loop")
     !
     !---------------------  solve impurity (CF basis)  ----------------------!
     if (lattice_flag)then
        call ed_solve(comm,Bath,Hloc_nnn(1:Nlat:2,:,:,:,:))
     else
        call ed_solve(comm,Bath_single,Hloc_nnn(1,:,:,:,:))
     endif
     !
     !---------------------  get sigmas     (CF basis)  ----------------------!
     if (lattice_flag)then
        allocate(Smats_hetero(Nlayer,Nspin,Nspin,Norb,Norb,Lmats));Smats_hetero=zero
        allocate(Sreal_hetero(Nlayer,Nspin,Nspin,Norb,Norb,Lreal));Sreal_hetero=zero
        call ed_get_sigma_matsubara(Smats_hetero,Nlayer)
        call ed_get_sigma_real(Sreal_hetero,Nlayer)
        call sigma_symmetrization()
        deallocate(Smats_hetero,Sreal_hetero)
     else
        allocate(Smats_single(Nspin,Nspin,Norb,Norb,Lmats));Smats_single=zero
        allocate(Sreal_single(Nspin,Nspin,Norb,Norb,Lreal));Sreal_single=zero
        call ed_get_sigma_matsubara(Smats_single)
        call ed_get_sigma_real(Sreal_single)
        call sigma_symmetrization()
        deallocate(Smats_single,Sreal_single)
     endif
     !
     !---------------------  get local Gf   (t2g basis) ----------------------!
     call dmft_gloc_matsubara(Comm,Hk,Wtk,Gmats,Smats,mpi_split='k')
     if(master)call dmft_print_gf_matsubara(Gmats,"Gloc_t2g",iprint=6)
     !
     !---------------------  get field      (t2g basis) ----------------------!
     if(cg_scheme=='weiss')then
        call dmft_weiss(Gmats,Smats,field,Hloc_nnn)
        if(master)call dmft_print_gf_matsubara(field,"Weiss_t2g",iprint=6)
     elseif(cg_scheme=='delta')then
        call dmft_delta(Gmats,Smats,field,Hloc_nnn)
        if(master)call dmft_print_gf_matsubara(field,"Delta_t2g",iprint=6)
     endif
     !
     !--------------------  rotate field   (t2g basis) ----------------------!
     if(diaglocalpbm)then
        call rotate_local_funct(field,U)
        if(master)then
           if(cg_scheme=='weiss')call dmft_print_gf_matsubara(field,"Weiss_CF",iprint=6)
           if(cg_scheme=='delta')call dmft_print_gf_matsubara(field,"Delta_CF",iprint=6)
        endif
     endif
     !
     !---------------------  mix field      (CF basis)  ----------------------!
     if(iloop>1)then
        field = wmixing*field + (1.d0-wmixing)*field_old
     endif
     field_old=field
     !
     !---------------------  get new field  (CF basis)  ----------------------!
     if (lattice_flag)then
        if(ed_para)then
           call ed_chi2_fitgf(Comm,Bath,field(1:Nlat:2,:,:,:,:,:),Hloc_nnn(1:Nlat:2,:,:,:,:),ispin=1)
           call spin_symmetrize_bath(Bath,save=.true.)
        else
           call ed_chi2_fitgf(Comm,Bath,field(1:Nlat:2,:,:,:,:,:),Hloc_nnn(1:Nlat:2,:,:,:,:),ispin=1)
           call ed_chi2_fitgf(Comm,Bath,field(1:Nlat:2,:,:,:,:,:),Hloc_nnn(1:Nlat:2,:,:,:,:),ispin=2)
        endif
     else
        call set_Hloc(Hloc_nnn(1,:,:,:,:))
        if(ed_para)then
           call ed_chi2_fitgf(Comm,field(1,:,:,:,:,:),Bath_single,ispin=1)
           call spin_symmetrize_bath(Bath_single,save=.true.)
        else
           call ed_chi2_fitgf(Comm,field(1,:,:,:,:,:),Bath_single,ispin=1)
           call ed_chi2_fitgf(Comm,field(1,:,:,:,:,:),Bath_single,ispin=2)
        endif
     endif
     !
     !------------------------  each loop operations  ------------------------!
     if(master)then
        !
        !chemical potential find
        converged_n=.true.
        sumdens=0d0
        xmu_old=xmu
        !
        !computing sumdens in different cases
        if(lattice_flag)then
           allocate(orb_dens_lat(Nlayer,Norb));orb_dens_lat=0.d0;call ed_get_dens(orb_dens_lat,Nlayer)
           allocate(orb_mag_lat(Nlayer,Norb)) ;orb_mag_lat=0.d0 ;call ed_get_mag(orb_mag_lat,Nlayer)
           do ilayer=1,Nlayer
              sumdens=sumdens+sum(orb_dens_lat(ilayer,:))/float(Nlayer)
              write(LOGfile,*)
              write(LOGfile,'(A7,I3,100F10.4)')"  Nlat: ",ilayer,orb_dens_lat(ilayer,:),orb_mag_lat(ilayer,:)
              write(LOGfile,*)
           enddo
           call write_Nmatrix_lattice()
           deallocate(orb_dens_lat,orb_mag_lat)
        else
           allocate(orb_dens_single(Norb)) ;orb_dens_single=0.d0;call ed_get_dens(orb_dens_single)
           allocate(orb_mag_single(Norb))  ;orb_mag_single=0.d0 ;call ed_get_mag(orb_mag_single)
           write(LOGfile,*)
           write(LOGfile,'(A7,I3,100F10.4)')"  Nlat: ",1,orb_dens_single(:),orb_mag_single(:)
           write(LOGfile,*)
           sumdens=sum(orb_dens_single)
           call write_Nmatrix_single()
           deallocate(orb_dens_single,orb_mag_single)
        endif
        write(LOGfile,*)"  n avrg:",sumdens
        !
        if(nread/=0.d0.and.look4n)then
           converged_n=.false.
           if(iloop>=2)call search_chempot(xmu,sumdens,converged_n)
        endif
        if(converged_n)then
           conv_n_loop=conv_n_loop+1
        else
           conv_n_loop=0
        endif
        !
        !convergence
        write(LOGfile,*)
        write(LOGfile,*) "   ------------------- convergence --------------------"
        allocate(conv_funct(Lmats));conv_funct=zero
        if (lattice_flag)then
           do i=1,Lmats
              conv_funct(i)=sum(nnn2lso_reshape(field(1:Nlat:2,:,:,:,:,i),Nlayer,Nspin,Norb))
           enddo
        else
           do i=1,Lmats
              conv_funct(i)=sum(nn2so_reshape(field(1,:,:,:,:,i),Nspin,Norb))
           enddo
        endif
        if(converged_n)converged = check_convergence(conv_funct,dmft_error,nsuccess,nloop)
        write(LOGfile,'(a35,L3)') "sigma converged",converged
        write(LOGfile,'(a35,L3)') "dens converged",converged_n
        converged = converged .and. converged_n
        write(LOGfile,'(a35,L3)') "total converged",converged
        write(LOGfile,'(a35,I3)') "global iloop",iloop
        write(LOGfile,'(a35,I3)') "times dens is ok",conv_n_loop
        write(LOGfile,*) "   ----------------------------------------------------"
        write(LOGfile,*)
        deallocate(conv_funct)
     endif
     call Bcast_MPI(Comm,xmu)
     call Bcast_MPI(Comm,converged)
     call MPI_Barrier(Comm,ier)
     !
     if(master)call end_loop
     !
  enddo
  !
  !
  !########################    POST-PROCESSING     ##################
  !
  !
  !------------------------  compute Gloc_CF(wm)  -------------------!
  call rotate_local_funct(Gmats,U)
  call dmft_print_gf_matsubara(Gmats,"Gloc_CF",iprint=6)
  !
  !
  !------------------------  compute Gloc_t2g(wr) -------------------!
  if(nread==0.d0)then
     call dmft_gloc_realaxis(Comm,Hk,Wtk,Greal,Sreal,mpi_split='k')
  else
     !
     allocate(zeta(NlNsNo,NlNsNo));zeta=zero
     allocate(Gloc(Nlat,Nspin,Nspin,Norb,Norb,Lreal));Gloc=zero
     !
     do ik =1+rank,Lk,siz
        do i=1,Lreal
           zeta=zero
           zeta=Hk(:,:,ik)+nnn2lso_reshape(Sreal(:,:,:,:,:,i),Nlat,Nspin,Norb)
           Gloc(:,:,:,:,:,i)=Gloc(:,:,:,:,:,i)+lso2nnn_reshape(inverse_g0k(dcmplx(wr(i),eps),zeta,Nlat,xmu)/Lk,Nlat,Nspin,Norb)
        enddo
     enddo
     call Mpi_AllReduce(Gloc,Greal,size(Greal),MPI_Double_Complex,MPI_Sum,Comm,ier)
     call MPI_Barrier(Comm,ier)
     deallocate(zeta,Gloc)
     !
  endif
  !
  if(master)call dmft_print_gf_realaxis(Greal,"Gloc_t2g",iprint=6)
  if(diaglocalpbm)then
     call rotate_local_funct(Greal,U)
     if(master)call dmft_print_gf_realaxis(Greal,"Gloc_CF",iprint=6)
  endif
  !
  !------   compute Bands  ------
  if(master.and.geometry=="bulk")call build_eigenbands("LVO_hr_bulk.dat","Bands.dat","Hk_path.dat","Kpoints_path.dat",Sreal)
  !
  call finalize_MPI()
  !
  !
  !
contains
  !
  !
  !
  !+------------------------------------------------------------------------------------------+!
  !PURPOSE: Perform the symmetry operations on the Sigma in the diagonal basis
  !         coming from the solver. Note that these symmetry operations acts only
  !         in the spin index, hence assuming an identical orbital ordering aming sites.
  !         This works only in the CF basis. A specific orital rotation for the orbital 
  !         index for sigmas in the same plane (or in different plane in bulk para/forced_sym 
  !         case) must be used if the imp is solved in the t2g basis where also the 
  !         off-diag sigmas are needed. 
  !         THIS SUB WORKS ONLY IF diaglocalpbm=TRUE
  !+------------------------------------------------------------------------------------------+!
  subroutine sigma_symmetrization()
    implicit none
    write(LOGfile,*) "  Self-energy symmetrization"
    if(.not.diaglocalpbm)write(LOGfile,'(A)') "!!!Warning!!! orbital structure missing"
    !
    if (lattice_flag)then
       if(ed_para)then
          !
          !I'm plugging impS in the neighboring site same plane no spin-flip
          do ilayer=1,Nlayer
             write(LOGfile,'(3(A,I3))') " plugghing impS nr.",ilayer," into ilat nr. ",2*ilayer-1," & ",2*ilayer
             !site 1 in plane - same spin - same layer
             Smats(2*ilayer-1,:,:,:,:,:)=Smats_hetero(ilayer,:,:,:,:,:)
             Sreal(2*ilayer-1,:,:,:,:,:)=Sreal_hetero(ilayer,:,:,:,:,:)
             !site 2 in plane - same spin - same layer
             Smats(2*ilayer,:,:,:,:,:)  =Smats_hetero(ilayer,:,:,:,:,:)
             Sreal(2*ilayer,:,:,:,:,:)  =Sreal_hetero(ilayer,:,:,:,:,:)
          enddo
          !
       elseif(.not.ed_para)then
          !
          do ilayer=1,Nlayer
             write(LOGfile,'(2(A,I3))') " plugghing impS nr.",ilayer," into ilat nr. ",2*ilayer-1
             !site 1 in plane - same spin - same layer
             Smats(2*ilayer-1,:,:,:,:,:)=Smats_hetero(ilayer,:,:,:,:,:)
             Sreal(2*ilayer-1,:,:,:,:,:)=Sreal_hetero(ilayer,:,:,:,:,:)
             write(LOGfile,'(2(A,I3))') " plugghing spin-flipped impS nr.",ilayer," into ilat nr. ",2*ilayer
             !site 2 in plane - flip spin - same layer
             Smats(2*ilayer,1,1,:,:,:)  =Smats_hetero(ilayer,2,2,:,:,:)
             Smats(2*ilayer,2,2,:,:,:)  =Smats_hetero(ilayer,1,1,:,:,:)
             Sreal(2*ilayer,1,1,:,:,:)  =Sreal_hetero(ilayer,2,2,:,:,:)
             Sreal(2*ilayer,2,2,:,:,:)  =Sreal_hetero(ilayer,1,1,:,:,:)
          enddo
          !
       endif
    else
       if(ed_para)then
          !
          do ilat=1,Nlat
             Smats(ilat,:,:,:,:,:)=Smats_single
             Sreal(ilat,:,:,:,:,:)=Sreal_single
          enddo
          !
       elseif(.not.ed_para)then
          if(z_symmetry=="ANTIFERRO")then
             write(LOGfile,'(A,I5)') " AFM in all directions"
             !
             Smats(1,:,:,:,:,:)=Smats_single
             Smats(4,:,:,:,:,:)=Smats(1,:,:,:,:,:)
             Smats(2,1,1,:,:,:)=Smats_single(2,2,:,:,:)
             Smats(2,2,2,:,:,:)=Smats_single(1,1,:,:,:)
             Smats(3,:,:,:,:,:)=Smats(2,:,:,:,:,:)
             !
          elseif(z_symmetry=="FERRO")then
             write(LOGfile,'(A,I5)') " AFM in plane - ferro between planes"
             !
             Smats(1,:,:,:,:,:)=Smats_single
             Smats(3,:,:,:,:,:)=Smats(1,:,:,:,:,:)
             Smats(2,1,1,:,:,:)=Smats_single(2,2,:,:,:)
             Smats(2,2,2,:,:,:)=Smats_single(1,1,:,:,:)
             Smats(4,:,:,:,:,:)=Smats(2,:,:,:,:,:)
             !
          endif
       endif
    endif
    !
    !rotate sigmas from the imp diagonal basis to the non-diagonal t2g basis
    if(diaglocalpbm)then
       call dmft_print_gf_matsubara(Smats,"Smats_CF",iprint=6)
       call dmft_print_gf_realaxis(Sreal,"Sreal_CF",iprint=6)
       call rotate_local_funct(Smats,Udag)
       call rotate_local_funct(Sreal,Udag)
    endif
    call dmft_print_gf_matsubara(Smats,"Smats_t2g",iprint=6)
    call dmft_print_gf_realaxis(Sreal,"Sreal_t2g",iprint=6)
    !
  end subroutine sigma_symmetrization
  !
  !
  !
  !+------------------------------------------------------------------------------------------+!
  !PURPOSE: Read the Non interacting Hamiltonian from  file
  !         Also this is just for testing the correct interface with the
  !         translator of the W90 output
  !         The re-ordering part can be used or not, depending on what the user of W90 did.
  !+------------------------------------------------------------------------------------------+!
  subroutine read_myhk(fileHR,fileHk,fileHloc,fileKpoints,local_diagonal_basis,Efield)
    implicit none
    character(len=*)            ,intent(in)           ::   fileHR
    character(len=*)            ,intent(in)           ::   fileHk
    character(len=*)            ,intent(in)           ::   fileHloc
    character(len=*)            ,intent(in)           ::   fileKpoints
    logical                     ,intent(in)           ::   local_diagonal_basis
    logical                     ,intent(in)           ::   Efield
    real(8)                                           ::   R1(3),R2(3),R3(3)
    real(8)                                           ::   Ruc(Nlat,3)
    logical                                           ::   IOfile
    integer                                           ::   ndx,ios,unitIO
    integer                                           ::   P(NlNsNo,NlNsNo)
    real(8)                                           ::   mu
    real(8)         ,allocatable                      ::   Awt(:,:),var(:)
    integer         ,allocatable                      ::   Nkvec(:)
    real(8)         ,allocatable                      ::   Kvec(:,:)
    complex(8)      ,allocatable                      ::   Hloc(:,:)
    complex(8)      ,allocatable                      ::   Hk_tmp(:,:,:)
    complex(8)      ,allocatable                      ::   Potential_so(:,:)
    complex(8)      ,allocatable                      ::   Potential_nn(:,:,:,:,:)
    !
    character(len=32)                                 ::   fileDR
    integer                                           ::   Nw,nph!,Nphotons
    real(8)                                           ::   dumw,dumF,lvl
    real(8)                                           ::   Deltaw,wo,dt
    real(8)         ,allocatable                      ::   w(:),t(:),rndp(:)
    real(8)         ,allocatable                      ::   tflex(:,:)
    real(8)         ,allocatable                      ::   fieldvect(:,:,:,:)
    complex(8)      ,allocatable                      ::   Ew(:,:),Et(:,:)
    complex(8)      ,allocatable                      ::   At(:,:),Aw(:,:)
    complex(8)      ,allocatable                      ::   Hkt(:,:,:,:)
    complex(8)      ,allocatable                      ::   Hloct(:,:,:),Wt(:,:,:)
    complex(8)      ,allocatable                      ::   Gloct(:,:,:,:,:,:,:)
    complex(8)      ,allocatable                      ::   Gloct_aux(:,:,:,:,:,:,:)
    !
    !
    if(geometry=="bulk") then
       R1 = [ 1.d0, 0.d0, 0.d0 ]*10.35845665
       R2 = [ 0.d0, 1.d0, 0.d0 ]*10.45462699
       R3 = [ 0.d0, 0.d0, 1.d0 ]*14.69267364
       !
       Ruc(1,:) = 0.0 * R1 + 0.5 * R2 + 0.5 * R3
       Ruc(2,:) = 0.5 * R1 + 0.0 * R2 + 0.5 * R3
       Ruc(3,:) = 0.0 * R1 + 0.5 * R2 + 0.0 * R3
       Ruc(4,:) = 0.5 * R1 + 0.0 * R2 + 0.0 * R3
       !
       allocate(Nkvec(3));Nkvec=0;Nkvec=[Nk,Nk,Nk]
       Lk=Nk*Nk*Nk
       allocate(Kvec(Lk,3));Kvec=0d0
       !
    elseif(geometry=="hetero") then
       R1 = [ 1.d0,-1.d0, 0.d0 ]*7.544034205
       R2 = [ 1.d0, 1.d0, 0.d0 ]*7.544034205
       R3 = [ 0.d0, 0.d0, 1.d0 ]*49.45119675
       !
       Ruc(1,:) =  0.507500528*R1+0.005255428*R2+0.373321376*R3
       Ruc(2,:) = -0.007176847*R1+0.505266961*R2+0.373317900*R3
       Ruc(3,:) =  0.499897916*R1+0.007491222*R2+0.524851544*R3
       Ruc(4,:) =  0.000400200*R1+0.507499434*R2+0.524840303*R3
       Ruc(5,:) =  0.494510887*R1+0.001974406*R2+0.674543358*R3
       Ruc(6,:) =  0.005774613*R1+0.501984647*R2+0.674540998*R3
       Ruc(7,:) =  0.509842981*R1-0.009512102*R2+0.821921782*R3
       Ruc(8,:) = -0.009630883*R1+0.490490079*R2+0.821911583*R3
       !
       allocate(Nkvec(3));Nkvec=0;Nkvec=[Nk,Nk,1]
       Lk=Nk*Nk
       allocate(Kvec(Lk,3));Kvec=0d0
       !
    endif
    !
    !
    !
    allocate(Hk(NlNsNo,NlNsNo,Lk))                 ;Hk=zero 
    allocate(Wtk(Lk))                              ;Wtk=1.d0/Lk
    !
    allocate(Hloc(NlNsNo,NlNsNo))                  ;Hloc=zero
    allocate(Hloc_lso(NlNsNo,NlNsNo))              ;Hloc_lso=zero
    allocate(Hloc_nnn(Nlat,Nspin,Nspin,Norb,Norb)) ;Hloc_nnn=zero
    allocate(U(NlNsNo,NlNsNo))                     ;U=eye(NlNsNo)
    allocate(Udag(NlNsNo,NlNsNo))                  ;Udag=eye(NlNsNo)
    !
    !
    call Hk_order(P)
    !
    !
    if(master)write(LOGfile,*)" Bulk tot k-points:",Lk
    !
    !
    inquire(file=fileHk,exist=IOfile)
    if(IOfile)then
       if(master)then
          write(LOGfile,'(2A)') "  Reading existing Hk from:  ",fileHk
          call TB_read_hk(Hk,fileHk,Nspin*Norb*Nlat,1,1,Nlat,Nkvec,Kvec)
          call TB_read_Hloc(Hloc,reg(fileHloc//".w90"))
       endif
       call Bcast_MPI(Comm,Hk) 
       call Bcast_MPI(Comm,Hloc) 
    else
       if(master)write(LOGfile,'(2A)') "  Transforming HR from:  ",fileHR
       call TB_hr_to_hk(comm,R1,R2,R3,Hk,Hloc,fileHR,Nspin,Norb,Nlat,Nkvec,P,Kvec,fileHk,fileKpoints)
    endif
    !
    !
    if(fake_potential.and.geometry=="hetero")then
       allocate(Potential_so(NlNsNo,NlNsNo));Potential_so=zero
       allocate(Potential_nn(Nlat,Nspin,Nspin,Norb,Norb));Potential_nn=zero
       do ilayer=1,Nlayer
          do iorb=1,Norb
             do ispin=1,Nspin
                Potential_nn(2*ilayer-1,ispin,ispin,iorb,iorb)=1.44*(ilayer-1)/3-1.04   !-1.38*(ilayer-1)/3.d0+1.d0
                Potential_nn(2*ilayer,ispin,ispin,iorb,iorb)  =1.44*(ilayer-1)/3-1.04   !-1.38*(ilayer-1)/3.d0+1.d0
             enddo
          enddo
       enddo
       Potential_so=nnn2lso_reshape(Potential_nn,Nlat,Nspin,Norb)
       do ik=1,Lk
          Hk(:,:,ik)=Hk(:,:,ik)+Potential_so
       enddo
       deallocate(Potential_nn,Potential_so)
    endif
    !
    !
    !Hloc=zero
    !Hloc=sum(Hk,dim=3)/Lk
    call TB_write_Hloc(Hloc,reg(fileHloc//".w90"))
    !
    !
    if(local_diagonal_basis)then
       U=zero;Udag=zero
       call build_rotations(Hloc,Hloc_lso,U)
       Udag=transpose(conjg(U))
    else
       Hloc_lso=Hloc
    endif
    Hloc_nnn=lso2nnn_reshape(Hloc_lso,Nlat,Nspin,Norb)
    call TB_write_Hloc(Hloc_lso,reg(fileHloc//".used"))
    call TB_write_Hloc(U,reg("rotation.used"))
    if(master)write(LOGfile,*) " H(k) and Hloc linked"
    !
    !
    if(Efield)then
       !
       !------------------ FIELD DEFINITION ------------------
       Nw=0
       ios=0
       unitIO=free_unit()
       open(unit=unitIO,file="Fluence_w.dat",status="old",action="read",iostat=ios)
       do while (ios==0)
          read(unitIO,*,iostat=ios)
          Nw=Nw+1
       enddo
       close(unitIO)
       Nw=Nw-1
       if(master)write(LOGfile,'(A,1I8)') "  H(w) Frequencies: ",Nw
       if(master)write(LOGfile,'(A,1I8)') "  Number of windows: ",Nphotons+1
       !
       !
       if(allocated(w))    deallocate(w)    ;allocate(w(2*Nw))             ;w=0d0
       if(allocated(t))    deallocate(t)    ;allocate(t(Nt))               ;t=linspace(-tmax,tmax,Nt)
       if(allocated(rndp)) deallocate(rndp) ;allocate(rndp(Nt))            ;call random_number(rndp)!;write(*,*)rndp
       !
       if(allocated(Ew))   deallocate(Ew)   ;allocate(Ew(2*Nw,Nphotons+1)) ;Ew=zero
       if(allocated(Aw))   deallocate(Aw)   ;allocate(Aw(2*Nw,Nphotons+1)) ;Aw=zero
       if(allocated(Et))   deallocate(Et)   ;allocate(Et(2000,Nphotons+1)) ;Et=zero
       if(allocated(At))   deallocate(At)   ;allocate(At(2000,Nphotons+1)) ;At=zero
       !
       !1) read Fluence
       unitIO=free_unit()
       open(unit=unitIO,file="Fluence_w.dat",status="old",action="read",position="rewind")
       do i=1,Nw
          read(unitIO,*) dumw,dumF
          w(i+Nw)=dumw
          w(Nw-i+1)=-w(i+Nw)
          !
          if(w(i+Nw).le.6.8)then
             Ew(i+Nw,Nphotons+1)=dcmplx(sqrt(2.d0*dumF/electric_constant)*Bohr_radius,0d0) !* dcmplx(cos(rndp(i))*2*pi,sin(rndp(i))*2*pi)
             Ew(Nw-i+1,Nphotons+1)=Ew(i+Nw,Nphotons+1)
          endif
          !
       enddo
       close(unitIO)
       !
       !
       !2a) generate E(w) and photons
       Deltaw=w(2*Nw)/Nphotons
       do nph=1,Nphotons
          wo = (nph-1)*Deltaw + Deltaw/2
          do i=1,Nw
             Ew(i+Nw,nph)=Ew(i+Nw,Nphotons+1)*exp( -( (w(i+Nw) - wo ) / (Deltaw/1.5d0) )**2 )
             Ew(Nw-i+1,nph)=Ew(i+Nw,nph)
          enddo
       enddo
       !2b) print E(w)
       if(master)then
          unitIO=free_unit()
          open(unit=unitIO,file="E_w.dat",status="unknown",action="write",position="rewind")
             do i=1,2*Nw
             write(unitIO,'(3000F12.7)')  w(i),real(Ew(i,Nphotons+1)),(real(Ew(i,nph)),nph=1,Nphotons)
          enddo
          close(unitIO)
       endif
       !
       !
       !3a) generate A(w)
       do nph=1,Nphotons+1
          Aw(:,nph)=Ew(:,nph)/(Xi*w)
       enddo
       !3b) print A(w)
       if(master)then
          unitIO=free_unit()
          open(unit=unitIO,file="A_w.dat",status="unknown",action="write",position="rewind")
          do i=1,2*Nw
             write(unitIO,'(3000F12.7)')  w(i),aimag(Aw(i,Nphotons+1)),(aimag(Aw(i,nph)),nph=1,Nphotons)
          enddo
          close(unitIO)
       endif
       !
       !
       dt=0.01
       if(allocated(tflex))deallocate(tflex);allocate(tflex(Nt,Nphotons+1));tflex=0d0
       if(gauge=="A")then
          !
          !generate A(t)
          do nph=1,Nphotons+1
             tflex(:,nph)=linspace(-tmax,tmax,Nt)
             call invFourier(w,Aw(:,nph),t,At(:,nph))
             write(LOGfile,'(A,1I3,1F12.7)')"  photon#",nph,abs(At(Nt,nph))
             i=0
             do while (abs(real(At(Nt,nph))).gt.1e-5) !1e-5
                tflex(:,nph)=0d0;tflex(:,nph)=linspace(-(tmax+i*dt),(tmax+i*dt),Nt)
                call invFourier(w,Aw(:,nph),tflex(:,nph),At(:,nph))
                i=i+1
                write(LOGfile,'(A,1I3,A,1I6,A,2F12.7)')"  photon#",nph," it: ",i," tmax: ",tmax+i*dt,abs(At(Nt,nph))
             enddo
          enddo
          write(LOGfile,'(1A)') "  A(t) generated"
          !print A(t)
          if(master)then
             unitIO=free_unit()
             open(unit=unitIO,file="A_t.dat",status="unknown",action="write",position="rewind")
             do i=1,2000
                write(unitIO,'(3000F12.7)')  (abs(tflex(1,nph)-tflex(2,nph))*i,nph=1,Nphotons+1), &
                                             (real(At(i,nph)),nph=1,Nphotons+1)
             enddo
             close(unitIO)
          endif
          !generate E(t)
          do nph=1,Nphotons+1
             call invFourier(w,Ew(:,nph),tflex(:,nph),Et(:,nph))
          enddo
          write(LOGfile,'(1A)') "  E(t) generated"
          !print E(t)
          if(master)then
             unitIO=free_unit()
             open(unit=unitIO,file="E_t.dat",status="unknown",action="write",position="rewind")
             do i=1,2000
                write(unitIO,'(3000F12.7)')  (abs(tflex(1,nph)-tflex(2,nph))*i,nph=1,Nphotons+1), &
                                             (real(Et(i,nph)),nph=1,Nphotons+1)
             enddo
             close(unitIO)
          endif
          !
       elseif(gauge=="E")then
          !
          do nph=1,Nphotons+1
             tflex(:,nph)=linspace(-tmax,tmax,Nt)
             call invFourier(w,Ew(:,nph),t,Et(:,nph))
             write(LOGfile,'(A,1I3,1F12.7)')"  photon#",nph,abs(Et(Nt,nph))
             i=0
             do while (abs(real(Et(Nt,nph))).gt.1e-5) !1e-5
                tflex(:,nph)=0d0;tflex(:,nph)=linspace(-(tmax+i*dt),(tmax+i*dt),Nt)
                call invFourier(w,Ew(:,nph),tflex(:,nph),Et(:,nph))
                i=i+1
                write(LOGfile,'(A,1I3,A,1I6,A,2F12.7)')"  photon#",nph," it: ",i," tmax: ",tmax+i*dt,abs(Et(Nt,nph))
             enddo
          enddo
          !print E(t)
          write(LOGfile,'(1A)') "  E(t) generated"
          if(master)then
             unitIO=free_unit()
             open(unit=unitIO,file="E_t.dat",status="unknown",action="write",position="rewind")
             do i=1,2000
                write(unitIO,'(3000F12.7)')  (abs(tflex(1,nph)-tflex(2,nph))*i,nph=1,Nphotons+1), &
                                             (real(Et(i,nph)),nph=1,Nphotons+1)
             enddo
             close(unitIO)
          endif
          !generate A(t)
          do nph=1,Nphotons+1
             call invFourier(w,Aw(:,nph),tflex(:,nph),At(:,nph))
          enddo
          write(LOGfile,'(1A)') "  A(t) generated"
          !print A(t)
          if(master)then
             unitIO=free_unit()
             open(unit=unitIO,file="A_t.dat",status="unknown",action="write",position="rewind")
             do i=1,2000
                write(unitIO,'(3000F12.7)')  (abs(tflex(1,nph)-tflex(2,nph))*i,nph=1,Nphotons+1), &
                                             (real(At(i,nph)),nph=1,Nphotons+1)
             enddo
             close(unitIO)
          endif
          !
          !
       endif
       !
       if(allocated(fieldvect))deallocate(fieldvect);allocate(fieldvect(2000,Nphotons+1,3,2)) ;fieldvect=0d0
       fieldvect(:,:,1,1)=real(Et); fieldvect(:,:,1,2)=real(At)
       fieldvect(:,:,2,1)=real(Et); fieldvect(:,:,2,2)=real(At)
       fieldvect(:,:,3,1)=0d0     ; fieldvect(:,:,3,2)=0d0
       !
       deallocate(w,t,Ew,Et,Aw,At)
       !
       !--------------------- DIPOLE --------------------
       if(allocated(var))deallocate(var);allocate(var(Norb));var=0d0
       var(1)=0.318358
       var(2)=0.213643
       var(3)=0.340087
       !
       fileDR=reg("dipole_bulk.dat")
       inquire(file=fileDR,exist=IOfile)
       if(.not.IOfile)then
          if(master)write(LOGfile,'(1A)') "  Dipole not found-->build"
          call TB_dipole(comm,R1,R2,R3,Ruc,fileHR,Norb,Nlat,fileDR,Nr,var,optimize=.false.  , &
                                                                         t_thresh_=0.0001d0 , &
                                                                         cg_niter_=cg_Niter , &
                                                                         cg_Ftol_=cg_Ftol   )
       else
          if(master)write(LOGfile,'(1A)') "  Dipole found"
       endif
       deallocate(var)
       !
       !--------------------- HAMILTONIAN --------------------
       if(allocated(Wt))deallocate(Wt);allocate(Wt(NlNsNo,Nt+10,Nphotons+1));Wt=zero
       do nph=1,Nphotons+1
          if(master)write(LOGfile,'(A,1I3,1A4,1I3)') "  Photon",nph," of ",Nphotons+1
          if(allocated(Hloct))deallocate(Hloct);allocate(Hloct(NlNsNo,NlNsNo,Nt+10))  ;Hloct =zero
          !
          call TB_hr_to_hk(comm,fieldvect(:,nph,:,:),gauge,R1,R2,R3,Ruc,Hloct,fileHR,fileDR,Nspin,Norb,Nlat,Nt+10,P)
          !
          !rotate Hloc to CF
          do i=1,Nt+10
             Hloct(:,:,i)=matmul(Udag,matmul(Hloct(:,:,i),U))
          enddo
          !
          !print Hloc(t)
          unitIO=free_unit()
          open(unit=unitIO,file="Hloct_ph"//str(nph)//".dat",status="unknown",action="write",position="rewind")
          do i=1,Nt+10
             write(unitIO,'(1I8)') i
             do io=1,NlNsNo
                write(unitIO,'(90F12.8)') (real(Hloct(io,jo,i)),jo=1,NlNsNo),(aimag(Hloct(io,jo,i)),jo=1,NlNsNo)
             enddo
          enddo
          close(unitIO)
          deallocate(Hloct)
          !
          !excite diagonal hopping
          dumw=-2.d0*pi/(Planck_constant_in_eV_s*1e15)
          do i=1,Nt+10
             dumF = dumw * ( fieldvect(i,nph,1,2)*norm2(R1) + fieldvect(i,nph,2,2)*norm2(R2) + fieldvect(i,nph,3,2)*norm2(R3) )
             Wt(:,i,nph)=0.5*dcmplx(cos(dumF),sin(dumF))
          enddo
          !
          !print diagonal hopping
          unitIO=free_unit()
          open(unit=unitIO,file="Wt_ph"//str(nph)//".dat",status="unknown",action="write",position="rewind")
          do i=1,Nt+10
             write(unitIO,'(90F12.8)') abs(tflex(1,nph)-tflex(2,nph))*i,(real(Wt(j,i,nph)),j=1,NlNsNo),(aimag(Wt(j,i,nph)),j=1,NlNsNo)
          enddo
          close(unitIO)
          !
       enddo
       deallocate(tflex)
    endif
    !
    !
    !-----  Build the local GF in the spin-orbital Basis   -----
    if(computeG0loc)then
       if(geometry=="bulk")   mu=15.429
       if(geometry=="hetero") mu=7.329
       !
       !matsu freq
       if(master)write(LOGfile,'(1A)')"  Build G0loc(wm)"
       allocate(Gloc(Nlat,Nspin,Nspin,Norb,Norb,Lmats));Gloc=zero
       do ik=1+rank,Lk,siz
          do i=1,Lmats
             Gloc(:,:,:,:,:,i)=Gloc(:,:,:,:,:,i)+lso2nnn_reshape(inverse_g0k(xi*wm(i),Hk(:,:,ik),Nlat,mu)/Lk,Nlat,Nspin,Norb)
          enddo
       enddo
       call Mpi_AllReduce(Gloc,Gmats,size(Gmats),MPI_Double_Complex,MPI_Sum,Comm,ier)
       call MPI_Barrier(Comm,ier)
       deallocate(Gloc)
       if(master)call dmft_print_gf_matsubara(Gmats,"G0loc_t2g",iprint=6)
       if(diaglocalpbm)then
          call rotate_local_funct(Greal,U)
          if(master)call dmft_print_gf_matsubara(Gmats,"G0loc_CF",iprint=6)
       endif
       Gmats=zero
       !
       !real freq
       if(master)write(LOGfile,'(1A)')"  Build G0loc(wr)"
       allocate(Gloc(Nlat,Nspin,Nspin,Norb,Norb,Lreal));Gloc=zero
       do ik=1+rank,Lk,siz
          do i=1,Lreal
             Gloc(:,:,:,:,:,i)=Gloc(:,:,:,:,:,i)+lso2nnn_reshape(inverse_g0k(dcmplx(wr(i),eps),Hk(:,:,ik),Nlat,mu)/Lk,Nlat,Nspin,Norb)
          enddo
       enddo
       call Mpi_AllReduce(Gloc,Greal,size(Greal),MPI_Double_Complex,MPI_Sum,Comm,ier)
       call MPI_Barrier(Comm,ier)
       deallocate(Gloc)
       if(master)call dmft_print_gf_realaxis(Greal,"G0loc_t2g",iprint=6)
       if(diaglocalpbm)then
          call rotate_local_funct(Greal,U)
          if(master)call dmft_print_gf_realaxis(Greal,"G0loc_CF",iprint=6)
       endif
       Greal=zero
       !
    endif
    !
    deallocate(Hloc,Kvec,Nkvec)
    !
  end subroutine read_myhk
  !
  !
  !
  !+------------------------------------------------------------------------------------------+!
  !PURPOSE: Rotations that diagonalizes the lattice local hamiltonians
  !+------------------------------------------------------------------------------------------+!
  subroutine build_rotations(Hloc_lso_in,Hloc_lso_out,rot_lso_,Hloc_nnn_out_)
    implicit none
    complex(8),allocatable,intent(in)                 ::   Hloc_lso_in(:,:)
    complex(8),allocatable,intent(out)                ::   Hloc_lso_out(:,:)
    complex(8),allocatable,intent(out),optional       ::   rot_lso_(:,:)
    complex(8),allocatable,intent(out),optional       ::   Hloc_nnn_out_(:,:,:,:,:)
    complex(8),allocatable                            ::   rot_lso(:,:)
    complex(8),allocatable                            ::   Hloc_nnn_out(:,:,:,:,:)
    complex(8),allocatable                            ::   Hloc_nnn_in(:,:,:,:,:)
    complex(8),allocatable                            ::   rot_nnn(:,:,:,:,:)
    complex(8),allocatable                            ::   arg(:,:)
    real(8)   ,allocatable                            ::   eig(:)
    !
    allocate(Hloc_nnn_in(Nlat,Nspin,Nspin,Norb,Norb));Hloc_nnn_in=zero
    allocate(rot_nnn(Nlat,Nspin,Nspin,Norb,Norb));rot_nnn=zero
    allocate(Hloc_lso_out(NlNsNo,NlNsNo));Hloc_lso_out=zero
    allocate(arg(Norb,Norb));arg=zero
    allocate(eig(Norb));eig=0.d0
    allocate(rot_lso(NlNsNo,NlNsNo));rot_lso=zero
    allocate(Hloc_nnn_out(Nlat,Nspin,Nspin,Norb,Norb));Hloc_nnn_out=zero
    !
    Hloc_nnn_in=lso2nnn_reshape(Hloc_lso_in,Nlat,Nspin,Norb)
    !
    do ilat=1,Nlat
       do ispin=1,Nspin
          arg=zero;eig=0.0d0
          arg=Hloc_nnn_in(ilat,ispin,ispin,:,:)
          call eigh(arg,eig,'V','U')
          rot_nnn(ilat,ispin,ispin,:,:)=arg
       enddo
    enddo
    !
    !outputs
    rot_lso=nnn2lso_reshape(rot_nnn,Nlat,Nspin,Norb)
    Hloc_lso_out=matmul(transpose(conjg(rot_lso)),matmul(Hloc_lso_in,rot_lso))
    Hloc_nnn_out=lso2nnn_reshape(Hloc_lso_out,Nlat,Nspin,Norb)
    if(present(rot_lso_))rot_lso_=rot_lso
    if(present(Hloc_nnn_out_))Hloc_nnn_out_=Hloc_nnn_out
    !
    deallocate(Hloc_nnn_in,rot_nnn,arg,eig,rot_lso,Hloc_nnn_out)
    !
  end subroutine build_rotations
  !
  !
  !

  !+------------------------------------------------------------------------------------------+!
  !PURPOSE: solve H(k) along path in the BZ.
  !+------------------------------------------------------------------------------------------+!
  subroutine build_eigenbands(fileHR,fileband,fileHk_path,fileKpoints_path,Sreal_)
    implicit none
    character(len=*)            ,intent(in)           ::   fileHR
    character(len=*)            ,intent(in),optional  ::   fileband,fileHk_path,fileKpoints_path
    complex(8)      ,allocatable,intent(in),optional  ::   Sreal_(:,:,:,:,:,:)
    integer                                           ::   Npts,Nkpathread
    integer                                           ::   P(Nlat*Nspin*Norb,Nlat*Nspin*Norb)
    real(8)         ,allocatable                      ::   kpath(:,:),kgrid(:,:),Scorr(:,:)
    complex(8)      ,allocatable                      ::   Hkpath(:,:,:)
    complex(8)      ,allocatable                      ::   Gkreal(:,:,:,:,:,:,:)
    complex(8)      ,allocatable                      ::   Gkr(:,:,:,:)
    type(rgb_color) ,allocatable                      ::   colors(:),colors_orb(:)
    logical                                           ::   IOfile
    !
    call Hk_order(P)
    !
    allocate(colors(NlNsNo))
    allocate(colors_orb(Norb))
    colors_orb=[red1,green1,blue1]
    do i=1,Nspin*Nlat
       colors(1+(i-1)*Norb:Norb+(i-1)*Norb)=colors_orb
    enddo
    !
    write(LOGfile,*)
    write(LOGfile,*)"Build bulk H(k) along the path M-R-G-M-X-G-X"
    write(LOGfile,*)
    Npts = 7
    Lk=(Npts-1)*Nkpath
    allocate(kpath(Npts,3))
    kpath(1,:)=kpoint_M1
    kpath(2,:)=kpoint_R
    kpath(3,:)=kpoint_Gamma
    kpath(4,:)=kpoint_M1
    kpath(5,:)=kpoint_X1
    kpath(6,:)=kpoint_Gamma
    kpath(7,:)=kpoint_X1
    !
    allocate(kgrid(Lk,3))  ;kgrid=0d0
    allocate(Hkpath(NlNsNo,NlNsNo,Lk));Hkpath=zero
    allocate(Gkreal(Lk,Nlat,Nspin,Nspin,Norb,Norb,Lreal));Gkreal=zero
    allocate(Scorr(NlNsNo,NlNsNo));Scorr=0d0
    if(present(Sreal_))Scorr=real(nnn2lso_reshape(Sreal_(:,:,:,:,:,1),Nlat,Nspin,Norb),8)
    !
    inquire(file=fileHk_path,exist=IOfile)
    !
    if(IOfile)then
       write(LOGfile,*) "   Reading existing Hkpath on: ",fileHk_path

       call TB_read_hk(Hkpath,fileHk_path,Nspin*Norb*Nlat,Nkpathread,kpath,kgrid)
       if(Nkpathread.ne.Nkpath) stop "Eigenbands wrong Nkpath readed"
    else
       write(LOGfile,*) "   Solving model on path"
       call TB_solve_model(   fileHR,Nspin,Norb,Nlat,kpath,Nkpath,colors               &
                          ,   [character(len=20) ::'M', 'R', 'G', 'M', 'X', 'G', 'X']  &
                          ,   P                                                        &
                          ,   fileband                                                 &
                          ,   fileHk_path                                              &
                          ,   fileKpoints_path                                         &
                          ,   Scorr                                                    &
                          ,   Hkpath                                                   &
                          ,   kgrid                                                    )
       !
    endif
    !
    allocate(Gkr(Lk,Nspin*Nlat*Norb,Nspin*Nlat*Norb,Lreal));Gkr=zero
    do ik=1,Lk
       call dmft_gk_realaxis(Hkpath(:,:,ik),1.d0/Lk,Gkreal(ik,:,:,:,:,:,:),Sreal)
       !faccio questa cosa qui sotto per separare per bene i due blocchi di spin
       do ifreq=1,Lreal
          Gkr(ik,:,:,ifreq)=matmul(P,matmul(nnn2lso_reshape(Gkreal(ik,:,:,:,:,:,ifreq),Nlat,Nspin,Norb),transpose(P)))
       enddo
    enddo
    !
    open(unit=106,file='Akw_s1.dat',status='unknown',action='write',position='rewind')
    open(unit=107,file='Akw_s2.dat',status='unknown',action='write',position='rewind')
    do ifreq=1,Lreal
       write(106,'(9000F18.12)')wr(ifreq),(30.*trace(-aimag(Gkr(ik,1:Nlat*Norb,1:Nlat*Norb,ifreq))/pi)+10.*ik,ik=1,Lk)
       write(107,'(9000F18.12)')wr(ifreq),(30.*trace(-aimag(Gkr(ik,1+Nlat*Norb:Nlat*Nspin*Norb,1+Nlat*Norb:Nlat*Nspin*Norb,ifreq))/pi)+10.*ik,ik=1,Lk)
    enddo
    close(106)
    close(107)
    write(LOGfile,*)"Im done on the path"
    !
    deallocate(kgrid,Hkpath,Gkreal,Scorr,Gkr,colors,colors_orb)
    !
  end subroutine build_eigenbands
  !
  !
  !
  !____________________________________________________________________________________________!
  !                                       Gfs
  !____________________________________________________________________________________________!
  !+------------------------------------------------------------------------------------------+!
  !PURPOSE: G0_loc functions
  !+------------------------------------------------------------------------------------------+!
  function inverse_g0k(iw,hk_,Nlat,mu_) result(g0k)
    implicit none
    complex(8),intent(in)                                  :: iw
    complex(8),dimension(Nlat*Nspin*Norb,Nlat*Nspin*Norb)  :: hk_
    real(8),intent(in),optional                            :: mu_
    real(8)                                                :: mu
    complex(8),dimension(Nlat*Nspin*Norb,Nlat*Nspin*Norb)  :: g0k,g0k_tmp
    integer                                                :: i,ndx,Nlat
    integer (kind=4), dimension(6)                         :: ipiv
    integer (kind=1)                                       :: ok
    integer (kind=4), parameter                            :: lwork=2000
    complex (kind=8), dimension(lwork)                     :: work
    real    (kind=8), dimension(lwork)                     :: rwork
    !
    mu=0.d0
    if(present(mu_))mu=mu_
    g0k=zero;g0k_tmp=zero
    !
    g0k=(iw+mu)*eye(Nlat*Nspin*Norb)-hk_
    g0k_tmp=g0k
    !
    call inv(g0k)
    call inversion_test(g0k,g0k_tmp,1.e-6,Nlat)
  end function inverse_g0k
  !
  !
  !
  !____________________________________________________________________________________________!
  !                                     utilities
  !____________________________________________________________________________________________!
  !+------------------------------------------------------------------------------------------+!
  !PURPOSE: Rotate function with specific rotation
  !+------------------------------------------------------------------------------------------+!
  subroutine rotate_local_funct(funct,rotation)
    implicit none
    complex(8),allocatable,intent(inout)              ::   funct(:,:,:,:,:,:)
    complex(8),allocatable,intent(in)                 ::   rotation(:,:)
    complex(8),allocatable                            ::   funct_in(:,:)
    complex(8),allocatable                            ::   funct_out(:,:)
    !
    allocate(funct_in(NlNsNo,NlNsNo));funct_in=zero
    allocate(funct_out(NlNsNo,NlNsNo));funct_out=zero
    Lfreq=size(funct,6)
    !
    do ifreq=1,Lfreq
       funct_in=zero;funct_out=zero
       funct_in=nnn2lso_reshape(funct(:,:,:,:,:,ifreq),Nlat,Nspin,Norb);funct(:,:,:,:,:,ifreq)=zero
       funct_out=matmul(transpose(conjg(rotation)),matmul(funct_in,rotation))
       funct(:,:,:,:,:,ifreq)=lso2nnn_reshape(funct_out,Nlat,Nspin,Norb)
    enddo
    deallocate(funct_in,funct_out)
    !
  end subroutine rotate_local_funct
  !
  !
  !
  !+------------------------------------------------------------------------------------------+!
  !PURPOSE: Put in proper order the input coming from w90. Depends on the w90 users.
  !+------------------------------------------------------------------------------------------+!
  subroutine Hk_order(Porder)
    implicit none
    integer   ,intent(out)                       :: Porder(Nlat*Nspin*Norb,Nlat*Nspin*Norb)
    integer   ,allocatable,dimension(:,:)        :: shift2
    integer                                      :: P2(Nlat*Nspin*Norb,Nlat*Nspin*Norb)
    integer                                      :: io1,jo1,io2,jo2
    !
    !-----  Ordering 2: as used in the code [[[Norb],Nspin],Nlat]   -----
    ndx=0
    do ilat=1,Nlat
       do ispin=1,Nspin
          do iorb=1,Norb
             !input
             io1 = iorb + (ilat-1)*Norb + (ispin-1)*Norb*Nlat
             !output
             io2 = iorb + (ispin-1)*Norb + (ilat-1)*Norb*Nspin
             !
             if(io1.ne.io2) ndx=ndx+1
          enddo
       enddo
    enddo
    allocate(shift2(ndx,2));shift2=0
    ndx=0
    do ilat=1,Nlat
       do ispin=1,Nspin
          do iorb=1,Norb
             !input
             io1 = iorb + (ilat-1)*Norb + (ispin-1)*Norb*Nlat
             !output
             io2 = iorb + (ispin-1)*Norb + (ilat-1)*Norb*Nspin
             !
             if(io1.ne.io2) then
                ndx=ndx+1
                shift2(ndx,:)=[io1,io2]
             endif
          enddo
       enddo
    enddo
    P2=0;P2=int(eye(Nlat*Nspin*Norb))
    do i=1,size(shift2,1)
       do j=1,2
          P2(shift2(i,j),shift2(i,j))=0
       enddo
       P2(shift2(i,1),shift2(i,2))=1
    enddo
    !
    !--------------------  Global reordering   -------------------------
    Porder=P2
    !
  end subroutine Hk_order
  !
  !
  !
  !+------------------------------------------------------------------------------------------+!
  !PURPOSE: Inversion test
  !+------------------------------------------------------------------------------------------+!
  subroutine inversion_test(A,B,tol,Nlat)
    implicit none
    integer (kind=4), intent(in)   ::   Nlat
    complex (kind=8), intent(in)   ::   A(Nlat*Nspin*Norb,Nlat*Nspin*Norb)
    complex (kind=8), intent(in)   ::   B(Nlat*Nspin*Norb,Nlat*Nspin*Norb)
    real    (kind=4), intent(in)   ::   tol
    real    (kind=4)               ::   error
    integer (kind=2)               ::   dime

    if (size(A).ne.size(B)) then
       write(LOGfile,*) "Matrices not equal cannot perform inversion test"
       stop
    endif
    dime=maxval(shape(A))
    error=abs(float(dime)-real(sum(matmul(A,B))))
    if (error.gt.tol) write(LOGfile,*) "inversion test fail",error
  end subroutine inversion_test
  !
  !
  !
  !+------------------------------------------------------------------------------------------+!
  !PURPOSE: Fourier
  !+------------------------------------------------------------------------------------------+!
  subroutine invFourier(w,func_in,t,func_out)
    implicit none
    real(8)          ,intent(in)   ::   w(:),t(:)
    complex(8)       ,intent(in)   ::   func_in(:)
    complex(8)       ,intent(out)  ::   func_out(size(t))
    real(8)                        ::   dt,dw
    integer                        ::   it,iw
    !
    if(size(func_in) .ne.size(w))stop "wrong size Fourier"
    !
    dw=abs(w(2)-w(1))
    dt=abs(t(2)-t(1))
    !
    func_out=zero
    do it=1,size(t)
       do iw=1,size(w)
          func_out(it) = func_out(it) + dw*func_in(iw)*dcmplx(cos(w(iw)*t(it)),-sin(w(iw)*t(it)))/sqrt(2*pi)
       enddo
    enddo
    !
  end subroutine invFourier
  !
  subroutine dirFourier(t,func_in,w,func_out)
    implicit none
    real(8)          ,intent(in)   ::   w(:),t(:)
    complex(8)       ,intent(in)   ::   func_in(:)
    complex(8)       ,intent(out)  ::   func_out(size(t))
    real(8)                        ::   dt,dw
    integer                        ::   it,iw
    !
    if(size(func_in) .ne.size(t))stop "wrong size Fourier"
    !
    dw=abs(w(2)-w(1))
    dt=abs(t(2)-t(1))
    !
    func_out=zero
    do iw=1,size(w)
       do it=1,size(t)
          func_out(iw) = func_out(iw) + dt*func_in(it)*dcmplx(cos(w(iw)*t(it)),sin(w(iw)*t(it)))/sqrt(2*pi)
       enddo
    enddo
    !
  end subroutine dirFourier
  !
  !
  !
  !+------------------------------------------------------------------------------------------+!
  !PURPOSE: just to get rid of some space
  !+------------------------------------------------------------------------------------------+!
  subroutine write_Nmatrix_lattice()
    allocate(Nmatrix_so(NlNsNo,NlNsNo))             ; Nmatrix_so=zero
    allocate(Nmatrix_nn(Nlat,Nspin,Nspin,Norb,Norb)); Nmatrix_nn=zero
    do ilayer=1,Nlayer
       do iorb=1,Norb
          !site A on ith-layer
          Nmatrix_nn(2*ilayer-1,1,1,iorb,iorb)=cmplx(0.5*(orb_dens_lat(ilayer,iorb)+orb_mag_lat(ilayer,iorb)),0.d0)
          Nmatrix_nn(2*ilayer-1,2,2,iorb,iorb)=cmplx(0.5*(orb_dens_lat(ilayer,iorb)-orb_mag_lat(ilayer,iorb)),0.d0)
          !site B on ith-layer
          if(ed_para)then
             Nmatrix_nn(2*ilayer,1,1,iorb,iorb)=cmplx(0.5*(orb_dens_lat(ilayer,iorb)+orb_mag_lat(ilayer,iorb)),0.d0)
             Nmatrix_nn(2*ilayer,2,2,iorb,iorb)=cmplx(0.5*(orb_dens_lat(ilayer,iorb)-orb_mag_lat(ilayer,iorb)),0.d0)
          else
             Nmatrix_nn(2*ilayer,1,1,iorb,iorb)=cmplx(0.5*(orb_dens_lat(ilayer,iorb)-orb_mag_lat(ilayer,iorb)),0.d0)
             Nmatrix_nn(2*ilayer,2,2,iorb,iorb)=cmplx(0.5*(orb_dens_lat(ilayer,iorb)+orb_mag_lat(ilayer,iorb)),0.d0)
          endif
       enddo
    enddo
    !
    !printing out  densities
    open(unit=106,file="N_CF_basis.dat",status="unknown",action="write",position="rewind")
    open(unit=107,file="S_CF_basis.dat",status="unknown",action="write",position="rewind")
    do iorb=1,Norb
       write(106,'(1000F15.7)')(real(Nmatrix_nn(ilat,1,1,iorb,iorb)+Nmatrix_nn(ilat,2,2,iorb,iorb)),ilat=1,Nlat)
       write(107,'(1000F15.7)')(real(Nmatrix_nn(ilat,1,1,iorb,iorb)-Nmatrix_nn(ilat,2,2,iorb,iorb)),ilat=1,Nlat)
    enddo
    close(106)
    close(107)
    Nmatrix_so=matmul(U,matmul(nnn2lso_reshape(Nmatrix_nn,Nlat,Nspin,Norb),Udag));Nmatrix_nn=zero
    Nmatrix_nn=lso2nnn_reshape(Nmatrix_so,Nlat,Nspin,Norb)
    open(unit=106,file="N_t2g_basis.dat",status="unknown",action="write",position="rewind")
    open(unit=107,file="S_t2g_basis.dat",status="unknown",action="write",position="rewind")
    do iorb=1,Norb
       write(106,'(1000F15.7)')(real(Nmatrix_nn(ilat,1,1,iorb,iorb)+Nmatrix_nn(ilat,2,2,iorb,iorb)),ilat=1,Nlat)
       write(107,'(1000F15.7)')(real(Nmatrix_nn(ilat,1,1,iorb,iorb)-Nmatrix_nn(ilat,2,2,iorb,iorb)),ilat=1,Nlat)
    enddo
    close(106)
    close(107)
    deallocate(Nmatrix_so,Nmatrix_nn)
  end subroutine write_Nmatrix_lattice
  !
  !
  subroutine write_Nmatrix_single()
    allocate(Nmatrix_so(NlNsNo,NlNsNo))             ; Nmatrix_so=zero
    allocate(Nmatrix_nn(Nlat,Nspin,Nspin,Norb,Norb)); Nmatrix_nn=zero
    do ilayer=1,Nlayer
       do iorb=1,Norb
          !site A on ith-layer
          Nmatrix_nn(2*ilayer-1,1,1,iorb,iorb) =cmplx(0.5*(orb_dens_single(iorb)+orb_mag_single(iorb)),0.d0)
          Nmatrix_nn(2*ilayer-1,2,2,iorb,iorb) =cmplx(0.5*(orb_dens_single(iorb)-orb_mag_single(iorb)),0.d0)
          !site B on ith-layer
          if(ed_para)then
             Nmatrix_nn(2*ilayer,1,1,iorb,iorb)=cmplx(0.5*(orb_dens_single(iorb)+orb_mag_single(iorb)),0.d0)
             Nmatrix_nn(2*ilayer,2,2,iorb,iorb)=cmplx(0.5*(orb_dens_single(iorb)-orb_mag_single(iorb)),0.d0)
          else
             Nmatrix_nn(2*ilayer,1,1,iorb,iorb)=cmplx(0.5*(orb_dens_single(iorb)-orb_mag_single(iorb)),0.d0)
             Nmatrix_nn(2*ilayer,2,2,iorb,iorb)=cmplx(0.5*(orb_dens_single(iorb)+orb_mag_single(iorb)),0.d0)
          endif
       enddo
    enddo
    !
    !printing out  densities
    open(unit=106,file="N_CF_basis.dat",status="unknown",action="write",position="rewind")
    open(unit=107,file="S_CF_basis.dat",status="unknown",action="write",position="rewind")
    do iorb=1,Norb
       write(106,'(1000F15.7)')(real(Nmatrix_nn(ilat,1,1,iorb,iorb)+Nmatrix_nn(ilat,2,2,iorb,iorb)),ilat=1,Nlat)
       write(107,'(1000F15.7)')(real(Nmatrix_nn(ilat,1,1,iorb,iorb)-Nmatrix_nn(ilat,2,2,iorb,iorb)),ilat=1,Nlat)
    enddo
    close(106)
    close(107)
    Nmatrix_so=matmul(U,matmul(nnn2lso_reshape(Nmatrix_nn,Nlat,Nspin,Norb),Udag));Nmatrix_nn=zero
    Nmatrix_nn=lso2nnn_reshape(Nmatrix_so,Nlat,Nspin,Norb)
    open(unit=106,file="N_t2g_basis.dat",status="unknown",action="write",position="rewind")
    open(unit=107,file="S_t2g_basis.dat",status="unknown",action="write",position="rewind")
    do iorb=1,Norb
       write(106,'(1000F15.7)')(real(Nmatrix_nn(ilat,1,1,iorb,iorb)+Nmatrix_nn(ilat,2,2,iorb,iorb)),ilat=1,Nlat)
       write(107,'(1000F15.7)')(real(Nmatrix_nn(ilat,1,1,iorb,iorb)-Nmatrix_nn(ilat,2,2,iorb,iorb)),ilat=1,Nlat)
    enddo
    close(106)
    close(107)
    deallocate(Nmatrix_so,Nmatrix_nn)
  end subroutine write_Nmatrix_single
  !
  !
  !
end program ed_LVO_hetero

        






!    kpath( 1,:)=kpoint_Gamma
!    kpath( 2,:)=kpoint_X1
!    kpath( 3,:)=kpoint_M1
!    kpath( 4,:)=kpoint_X2
!    kpath( 5,:)=kpoint_Gamma
!    kpath( 6,:)=kpoint_X3
!    kpath( 7,:)=kpoint_M3
!    kpath( 8,:)=kpoint_R
!    kpath( 9,:)=kpoint_M2
!    kpath(10,:)=kpoint_X1
!    kpath(11,:)=kpoint_M1
!    kpath(12,:)=kpoint_X2
!    kpath(13,:)=kpoint_Gamma
!    kpath(14,:)=kpoint_X3
!    kpath(15,:)=kpoint_M3
!    kpath(16,:)=kpoint_R
!    kpath(17,:)=kpoint_M2
!    kpath(18,:)=kpoint_X3





!          if(master)write(LOGfile,'(A)')"  Build A(w,t)"
!          allocate(Gloct(Nlat,Nspin,Nspin,Norb,Norb,Lreal,Nt+10))     ;Gloct=zero
!          allocate(Gloct_aux(Nlat,Nspin,Nspin,Norb,Norb,Lreal,Nt+10)) ;Gloct_aux=zero
!          do ik=1+rank,Lk,siz

!  if(master)write(*,*)ik

!             do i=1,Lreal
!                do j=1,Nt+10
!                   Gloct_aux(:,:,:,:,:,i,j) = Gloct_aux(:,:,:,:,:,i,j) + &
!                lso2nnn_reshape(inverse_g0k(dcmplx(wr(i),eps),Hkt(:,:,ik,j),Nlat,mu)/Lk,Nlat,Nspin,Norb)
!                enddo
!             enddo
!          enddo
!          call Mpi_AllReduce(Gloct_aux,Gloct,size(Gloct),MPI_Double_Complex,MPI_Sum,Comm,ier)
!          call MPI_Barrier(Comm,ier)
!          deallocate(Gloct_aux)
!          !
!          allocate(Gloc(Nlat,Nspin,Nspin,Norb,Norb,Lreal));Gloc=zero
!          do j=1,Nt+10
!             Gloc=Gloct(:,:,:,:,:,:,j)
!             call rotate_local_funct(Gloc,U)
!             Gloct(:,:,:,:,:,:,j)=Gloc
!          enddo
!          deallocate(Gloc)
!          !
!          if(master)then
!             !
!             unitIO=free_unit()
!             open(unit=unitIO,file="Awt_l11_"//str(nph)//".dat",status="unknown",action="write",position="rewind")
!             do i=1,Lreal
!                write(unitIO,'(3000F12.7)')wr(i),(-aimag(Gloct(1,1,1,1,1,i,j))/pi,j=1,Nt+10)
!             enddo
!             close(unitIO)
!             !
!             unitIO=free_unit()
!             open(unit=unitIO,file="Awt_l22_"//str(nph)//".dat",status="unknown",action="write",position="rewind")
!             do i=1,Lreal
!                write(unitIO,'(3000F12.7)')wr(i),(-aimag(Gloct(1,1,1,2,2,i,j))/pi,j=1,Nt+10)
!             enddo
!             close(unitIO)
!             !
!             unitIO=free_unit()
!             open(unit=unitIO,file="Awt_l33_"//str(nph)//".dat",status="unknown",action="write",position="rewind")
!             do i=1,Lreal
!                write(unitIO,'(3000F12.7)')wr(i),(-aimag(Gloct(1,1,1,3,3,i,j))/pi,j=1,Nt+10)
!             enddo
!             close(unitIO)
!          endif
!          !
!          !estimate bandwidth_CF vector here
!          lvl=1e-3
!          do j=1,Nt+10
!             do ilat=1,Nlat
!                do ispin=1,Nspin
!                   do iorb=1,Norb
!                      !
!                      io = iorb + (ispin-1)*Norb + (ilat-1)*Nspin*Norb
!                      !
!                      bottomloop:do i=1,Lreal
!                         if(abs(aimag(Gloct(ilat,ispin,ispin,iorb,iorb,i,j))/pi).gt.lvl)then
!                            Wt(io,j,nph,1)=wr(i)
!                            exit bottomloop
!                         endif
!                      enddo bottomloop
!                      !
!                      toploop:do i=Lreal,1,-1
!                         if(abs(aimag(Gloct(ilat,ispin,ispin,iorb,iorb,i,j))/pi).gt.lvl)then
!                            Wt(io,j,nph,2)=wr(i)
!                            exit toploop
!                         endif
!                      enddo toploop
!                      !
!                   enddo
!                enddo
!             enddo
!          enddo
!          deallocate(Gloct)
!          !
!          if(master)then
!             !
!             unitIO=free_unit()
!             open(unit=unitIO,file="W_ph"//str(nph)//".dat",status="unknown",action="write",position="rewind")
!             do j=1,Nt+10
!                write(unitIO,'(30F12.7)')abs(tflex(1,nph)-tflex(2,nph))*j,(Wt(io,j,nph,1),io=1,NlNsNo),(Wt(io,j,nph,2),io=1,NlNsNo)
!             enddo
!             close(unitIO)
!             !
!          endif
!          !





!    !
!    where(abs((Hloc))<1.d-1)Hloc=0d0
!    call TB_write_Hloc( Hloc(7:12,1:6)  ,reg("Tl21.w90"))
!    call TB_write_Hloc(Hloc(13:18,1:6)  ,reg("Tl31.w90"))
!    call TB_write_Hloc(Hloc(19:24,1:6)  ,reg("Tl41.w90"))
!    call TB_write_Hloc(Hloc(13:18,7:12) ,reg("Tl32.w90"))
!    call TB_write_Hloc(Hloc(19:24,7:12) ,reg("Tl42.w90"))
!    call TB_write_Hloc(Hloc(19:24,13:18),reg("Tl43.w90"))
!    !
!    call TB_write_Hloc(Hloc(4:6,1:3)    ,reg("ti1.w90"))
!    call TB_write_Hloc(Hloc(10:12,7:9)  ,reg("ti2.w90"))
!    call TB_write_Hloc(Hloc(16:18,13:15),reg("ti3.w90"))
!    call TB_write_Hloc(Hloc(22:24,19:21),reg("ti4.w90"))
!    !
!    where(abs((Hloc_lso))<1.d-1)Hloc_lso=0d0
!    call TB_write_Hloc( Hloc_lso(7:12,1:6)  ,reg("Tl21d.w90"))
!    call TB_write_Hloc(Hloc_lso(13:18,1:6)  ,reg("Tl31d.w90"))
!    call TB_write_Hloc(Hloc_lso(19:24,1:6)  ,reg("Tl41d.w90"))
!    call TB_write_Hloc(Hloc_lso(13:18,7:12) ,reg("Tl32d.w90"))
!    call TB_write_Hloc(Hloc_lso(19:24,7:12) ,reg("Tl42d.w90"))
!    call TB_write_Hloc(Hloc_lso(19:24,13:18),reg("Tl43d.w90"))
!    !
!    call TB_write_Hloc(Hloc_lso(4:6,1:3)    ,reg("ti1d.w90"))
!    call TB_write_Hloc(Hloc_lso(10:12,7:9)  ,reg("ti2d.w90"))
!    call TB_write_Hloc(Hloc_lso(16:18,13:15),reg("ti3d.w90"))
!    call TB_write_Hloc(Hloc_lso(22:24,19:21),reg("ti4d.w90"))
!    !










    !-----  Ordering 1: same orbital position for each Nlat block   -----
!    allocate(shift1(2,2));shift1=0
!    shift1(1,:)=[1,2]
!    shift1(2,:)=[7,8]
!    P1=0;P1=int(eye(Nlat*Nspin*Norb))
!    do i=1,size(shift1,1)
!       do j=1,2
!          P1(shift1(i,j),shift1(i,j))=0
!       enddo
!       P1(shift1(i,1),shift1(i,2))=1
!       P1(shift1(i,2),shift1(i,1))=1
!    enddo
!    P1(1+Nlat*Norb:Nlat*Norb*Nspin,1+Nlat*Norb:Nlat*Norb*Nspin)=P1(1:Nlat*Norb,1:Nlat*Norb)
    !
    !
    !-------------  Ordering 3: swapping site 2 with site 3   -----------
!    allocate(shift3(6,2));shift3=0
!    do i=1,Nspin*Norb
!       shift3(i,:)=[Nspin*Norb+i,2*Nspin*Norb+i]
!    enddo
!    ndx=0
!    P3=0;P3=int(eye(Nlat*Nspin*Norb))
!    do i=1,size(shift3,1)
!       do j=1,2
!          P3(shift3(i,j),shift3(i,j))=0
!       enddo
!       P3(shift3(i,1),shift3(i,2))=1
!       P3(shift3(i,2),shift3(i,1))=1
!    enddo



!     !kinetic energy
!     if(computeEk)then
!        allocate(Ekm(Lmats));                                        Ekm=0d0
!        allocate(Gkmats(Nk*Nk*Nk,Nlat,Nspin,Nspin,Norb,Norb,Lmats)); Gkmats=zero
!        do ik=1,Nk*Nk*Nk
!           call dmft_gk_matsubara(Comm,Hk(:,:,ik),1.d0/(Nk*Nk*Nk),Gkmats(ik,:,:,:,:,:,:),Smats)
!        enddo
!        do i=1,Lmats
!          do ik=1,Nk*Nk*Nk
!              Ekm(i)=Ekm(i)+trace(matmul(Hk(:,:,ik),nnn2lso_reshape(Gkmats(ik,:,:,:,:,:,i),Nlat,Nspin,Norb)))/(Nk*Nk*Nk)
!           enddo
!        enddo
!        Ek=sum(Ekm)/beta
!        write(LOGfile,*) "  Ekin:",Ek
!        if(master)then
!           open(unit=106,file="Ekin_all.dat",status="unknown",action="write",position="append")
!           write(106,'(I5,F15.7)')iloop, Ek
!           close(106)
!        endif
!        deallocate(Ekm,Gkmats)
!     endif
!     !




!    !DEBUG>>
!    Nlat_notfake=Nlat
!    if(present(Nlat_notfake_))then
!       Nlat_notfake=Nlat_notfake_
!       dim_plane=2*Nspin*Norb
!       dim_notfake=Nlat_notfake*Nspin*Norb
!       deallocate(Hk)
!       allocate(Hk(dim_notfake,dim_notfake,Nk*Nk*Nk));Hk=zero
!    endif
!    !>>DEBUG
!    !DEBUG>>
!    if(present(Nlat_notfake_))then
!       allocate(Hk_tmp(Nlat_notfake*Nspin*Norb,Nlat_notfake*Nspin*Norb,Nk*Nk*Nk));Hk_tmp=zero
!       Hk_tmp=Hk
!       deallocate(Hk)
!       allocate(Hk(NlNsNo,NlNsNo,Nk*Nk*Nk));Hk=zero
!       do i=1,fake_hetero !number of bulk repetitions
!          !diag block
!          Hk(1+dim_notfake*(i-1):dim_notfake*i,1+dim_notfake*(i-1):dim_notfake*i,:)=Hk_tmp
!       enddo
!       do i=1,fake_hetero-1
!          !up block
!          Hk(1+dim_plane+dim_notfake*(i-1):dim_notfake*i,1+dim_notfake*i:1+dim_plane+dim_notfake*i,:)=Hk_tmp(1:dim_plane,1+dim_plane:dim_notfake,:)
!          !dw block
!          Hk(1+dim_notfake*i:1+dim_plane+dim_notfake*i,1+dim_plane+dim_notfake*(i-1):dim_notfake*i,:)=Hk_tmp(1+dim_plane:dim_notfake,1:dim_plane,:)
!       enddo
!       deallocate(Hk_tmp)
!    endif
!    !>>DEBUG
