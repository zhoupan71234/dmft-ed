program ed_bhz_afm
  USE DMFT_ED
  USE SCIFOR
  USE DMFT_TOOLS
  implicit none
  integer                :: ip,iloop,Lk,Nso,Nlso,ispin,iorb
  logical                :: converged
  integer                :: Nindep,Nsites
  !Bath:
  integer                :: Nb
  real(8),allocatable    :: Bath(:,:),Bath_prev(:,:)
  !The local hybridization function:
  complex(8),allocatable :: Delta(:,:,:,:,:,:)
  complex(8),allocatable :: Smats(:,:,:,:,:,:)
  complex(8),allocatable :: Sreal(:,:,:,:,:,:)
  complex(8),allocatable :: Gmats(:,:,:,:,:,:)
  complex(8),allocatable :: Greal(:,:,:,:,:,:)
  !Hamiltonian input:
  complex(8),allocatable :: Hk(:,:,:),bhzHloc(:,:),Hloc(:,:,:,:,:)
  real(8),allocatable    :: Wtk(:)
  !variables for the model:
  integer                :: Nk
  real(8)                :: mh,lambda,wmixing,akrange
  character(len=16)      :: finput
  character(len=32)      :: hkfile
  logical                :: waverage,spinsym,sitesym,fullsym,getak,getdelta

  !Parse additional variables && read Input && read H(k)^4x4
  call parse_cmd_variable(finput,"FINPUT",default='inputED_BHZ.conf')
  call parse_input_variable(getak,"GETAK",finput,default=.false.)
  call parse_input_variable(getdelta,"GETDELTA",finput,default=.false.)
  call parse_input_variable(akrange,"AKRANGE",finput,default=10.d0)
  call parse_input_variable(hkfile,"HKFILE",finput,default="hkfile.in")
  call parse_input_variable(nk,"NK",finput,default=100)
  call parse_input_variable(mh,"MH",finput,default=0.d0)
  call parse_input_variable(wmixing,"WMIXING",finput,default=0.75d0)
  call parse_input_variable(waverage,"WAVERAGE",finput,default=.false.)
  call parse_input_variable(spinsym,"spinsym",finput,default=.false.)
  call parse_input_variable(sitesym,"sitesym",finput,default=.false.)
  call parse_input_variable(fullsym,"fullsym",finput,default=.true.)
  call parse_input_variable(lambda,"LAMBDA",finput,default=0.d0)
  call ed_read_input(trim(finput))

  if(sitesym.AND.fullsym)stop "sitesym AND fullsym both .true.! chose one symmetry!"

  Nindep=4                      !number of independent sites, 4 for AFM ordering
  Nsites=Nindep

  if(fullsym)then
     Nsites=1
     write(*,*)"Using Nindep sites=",Nsites
     write(*,*)"(site=2,l,s)=(site=1,l,-s)"
     write(*,*)"(site=3,l,s)=(site=1,l,-s)"
     write(*,*)"(site=4,l,s)=(site=1,l,s)"
     open(999,file="symmetries.used")
     write(999,*)"Symmetries used are:"
     write(999,*)"(site=2,l,s)=(site=1,l,-s)"
     write(999,*)"(site=3,l,s)=(site=1,l,-s)"
     write(999,*)"(site=4,l,s)=(site=1,l,s)"
     close(999)
  endif

  if(sitesym)then
     Nsites=2
     write(*,*)"Using Nindep sites=",Nsites
     write(*,*)"(site=4,l,s)=(site=1,l,s)"
     write(*,*)"(site=3,l,s)=(site=2,l,s)"
     open(999,file="symmetries.used")
     write(999,*)"Symmetries used are:"
     write(999,*)"(site=4,l,s)=(site=1,l,s)"
     write(999,*)"(site=3,l,s)=(site=2,l,s)"
     close(999)
  endif

  if(Nspin/=2.OR.Norb/=2)stop "wrong setup from input file: Nspin=Norb=2 -> 4Spin-Orbitals"
  Nso=Nspin*Norb
  Nlso=Nindep*Nso!=16
  if(spinsym)sb_field=0.d0

  !Allocate Weiss Field:
  allocate(delta(Nindep,Nspin,Nspin,Norb,Norb,Lmats))
  allocate(Smats(Nindep,Nspin,Nspin,Norb,Norb,Lmats))
  allocate(Sreal(Nindep,Nspin,Nspin,Norb,Norb,Lreal))
  allocate(Gmats(Nindep,Nspin,Nspin,Norb,Norb,Lmats))
  allocate(Greal(Nindep,Nspin,Nspin,Norb,Norb,Lreal))
  allocate(Hloc(Nindep,Nspin,Nspin,Norb,Norb))

  !Buil the Hamiltonian on a grid or on  path
  call build_hk(trim(hkfile))
  Hloc = lso2nnn_reshape(bhzHloc,Nindep,Nspin,Norb)

  !Setup solver
  Nb=get_bath_size()
  allocate(bath(Nindep,Nb))
  allocate(Bath_prev(Nindep,Nb))
  do ip=1,Nindep
     ed_file_suffix="_is"//reg(txtfy(ip))
     call ed_init_solver(bath(ip,:))
     call break_symmetry_bath(bath(ip,:),sb_field,(-1.d0)**(ip+1))
     write(LOGfile,*)"Updated Hloc, site:",ip
  enddo


  !DMFT loop
  iloop=0;converged=.false.
  do while(.not.converged.AND.iloop<nloop)
     iloop=iloop+1
     call start_loop(iloop,nloop,"DMFT-loop")

     !Solve the EFFECTIVE IMPURITY PROBLEM (first w/ a guess for the bath)
     do ip=1,Nsites
        write(LOGfile,*)"Solving site:",ip
        ed_file_suffix="_is"//reg(txtfy(ip))
        call set_hloc(Hloc(ip,:,:,:,:))
        call ed_solve(bath(ip,:))
        Smats(ip,:,:,:,:,:) = impSmats
        Sreal(ip,:,:,:,:,:) = impSreal
     enddo
     if(sitesym)then
        Smats(3,:,:,:,:,:) = Smats(2,:,:,:,:,:)
        Sreal(3,:,:,:,:,:) = Sreal(2,:,:,:,:,:)
        Smats(4,:,:,:,:,:) = Smats(1,:,:,:,:,:)
        Sreal(4,:,:,:,:,:) = Sreal(1,:,:,:,:,:)
     endif
     if(fullsym)then
        !step 1 extend the solution to ip=2 using the relations
        !A(ip=2,l,sigma) = A(ip=1,l,-sigma)
        do ispin=1,2
           Smats(2,ispin,ispin,:,:,:)=Smats(1,3-ispin,3-ispin,:,:,:)
           Sreal(2,ispin,ispin,:,:,:)=Sreal(1,3-ispin,3-ispin,:,:,:)
        enddo
        !step 2 extend the solution to other ip=3,4
        Smats(3,:,:,:,:,:) = Smats(2,:,:,:,:,:)
        Sreal(3,:,:,:,:,:) = Sreal(2,:,:,:,:,:)
        Smats(4,:,:,:,:,:) = Smats(1,:,:,:,:,:)
        Sreal(4,:,:,:,:,:) = Sreal(1,:,:,:,:,:)
     endif


     ! !Get the Weiss field/Delta function to be fitted (user defined)
     ! call get_delta
     ! compute the local gf:
     call ed_get_gloc_lattice(Hk,Wtk,Gmats,Greal,Smats,Sreal,iprint=1)
     ! compute the Weiss field
     call ed_get_weiss_lattice(Gmats,Smats,Delta,Hloc,iprint=1)

     !Fit the new bath, starting from the old bath + the supplied delta
     do ip=1,Nsites
        ed_file_suffix="_is"//reg(txtfy(ip))
        call set_hloc(Hloc(ip,:,:,:,:))
        call ed_chi2_fitgf(delta(ip,1,1,:,:,:),bath(ip,:),ispin=1)
        if(.not.spinsym)then
           call ed_chi2_fitgf(delta(ip,2,2,:,:,:),bath(ip,:),ispin=2)
        else
           call spin_symmetrize_bath(bath(ip,:))
        endif
     enddo


     if(fullsym)then
        do ispin=1,2
           !bath(2,:,ispin)=bath(1,:,3-ispin)
           call copy_component_bath(bath(1,:),3-ispin,bath(2,:),ispin)
        enddo
        bath(3,:)=bath(2,:)
        bath(4,:)=bath(1,:)
     elseif(sitesym)then
        bath(3,:)=bath(2,:)
        bath(4,:)=bath(1,:)
     elseif(.not.fullsym.AND..not.sitesym)then
        if(waverage)then
           bath(1,:)=(bath(1,:)+bath(4,:))/2.d0
           bath(2,:)=(bath(2,:)+bath(3,:))/2.d0
           bath(3,:)=bath(2,:)
           bath(4,:)=bath(1,:)
        endif
     endif

     !MIXING:
     do ip=1,Nsites
        if(iloop>1)bath(ip,:) = wmixing*bath(ip,:) + (1.d0-wmixing)*Bath_prev(ip,:)
        Bath_prev(ip,:)=bath(ip,:)
     enddo
     converged = check_convergence(delta(1,1,1,1,1,1:Lfit),dmft_error,nsuccess,nloop)

     call end_loop
  enddo



contains



  !--------------------------------------------------------------------!
  !PURPOSE: BUILD THE H(k) FOR THE BHZ-AFM MODEL.
  !--------------------------------------------------------------------!
  subroutine build_hk(file)
    character(len=*)                          :: file
    integer                                   :: i,j,ik=0
    integer                                   :: ix,iy
    real(8)                                   :: kx,ky    
    integer                                   :: iorb,jorb
    integer                                   :: isporb,jsporb
    integer                                   :: ispin,jspin
    real(8)                                   :: foo
    integer                                   :: unit
    complex(8),dimension(Nlso,Nlso)       :: Hkmix
    complex(8),dimension(Lmats,Nlso,Nlso) :: fg
    complex(8),dimension(Lreal,Nlso,Nlso) :: fgr
    real(8)                                   :: wm(Lmats),wr(Lreal),dw,n0(Nlso),eig(Nlso)
    wm = pi/beta*real(2*arange(1,Lmats)-1,8)
    wr = linspace(wini,wfin,Lreal,mesh=dw)
    call start_progress(LOGfile)
    write(LOGfile,*)"Build H(k) AFM-BHZ:"
    Lk=Nk**2
    allocate(Hk(Nlso,Nlso,Lk))
    unit=free_unit()
    open(unit,file=file)
    fg=zero
    fgr=zero
    do ix=1,Nk
       kx = -pi + 2.d0*pi*dble(ix-1)/dble(Nk)
       do iy=1,Nk
          ky = -pi + 2.d0*pi*dble(iy-1)/dble(Nk)
          ik=ik+1
          Hk(:,:,ik) = hk_bhz_afm(kx,ky)
          write(unit,"(3(F10.7,1x))")kx,ky,pi
          do i=1,Nlso
             write(unit,"(100(2F10.7,1x))")(Hk(i,j,ik),j=1,size(Hk,2))
          enddo
          if(Nk<=15)then
             do i=1,Lreal
                fgr(i,:,:)=fgr(i,:,:) + inverse_g0k(dcmplx(wr(i),eps)+xmu,Hk(:,:,ik))/dble(Lk)
             enddo
             do i=1,Lmats
                fg(i,:,:) =fg(i,:,:)  + inverse_g0k(xi*wm(i)+xmu,Hk(:,:,ik))/dble(Lk)
             enddo
          endif
          call progress(ik,Lk)
       enddo
    enddo
    call stop_progress()
    write(unit,*)""
    allocate(Wtk(Lk))
    Wtk=1.d0/dble(Lk)
    if(Nk<=15)then
       do i=1,Nlso
          n0(i) = -2.d0*sum(dimag(fgr(:,i,i))*fermi(wr(:),beta))*dw/pi
       enddo
       write(unit,"(24F20.12)")mh,lambda,xmu,(n0(i),i=1,Nlso),sum(n0)
       write(LOGfile,"(24F20.12)")mh,lambda,xmu,(n0(i),i=1,Nlso),sum(n0)
       open(10,file="U0_DOS.ed")
       do i=1,Lreal
          write(10,"(100(F25.12))") wr(i),(-dimag(fgr(i,iorb,iorb))/pi,iorb=1,Nlso)
       enddo
       close(10)
       open(11,file="U0_Gloc_iw.ed")
       do i=1,Lmats
          write(11,"(20(2F20.12))") wm(i),(fg(i,iorb,iorb),iorb=1,Nlso)
       enddo
       close(11)
    endif
    allocate(bhzHloc(Nlso,Nlso))
    bhzHloc = sum(Hk(:,:,:),dim=3)/dble(Lk)
    where(abs(dreal(bhzHloc))<1.d-9)bhzHloc=0.d0
    ! endif
    !
    write(*,*)"# of k-points     :",Lk
    write(*,*)"# of SO-bands     :",Nso
    write(*,*)"# of AFM-SO-bands :",Nlso
  end subroutine build_hk







  !--------------------------------------------------------------------!
  !BHZ - AFM HAMILTONIAN:
  !--------------------------------------------------------------------!
  function hk_bhz_afm(kx,ky) result(hk)
    real(8)                     :: kx,ky
    complex(8),dimension(16,16) :: hk,hktmp
    hktmp            = zero
    hktmp(1:8,1:8)   = hk_bhz_afm8x8(kx,ky)
    hktmp(9:16,9:16) = conjg(hk_bhz_afm8x8(-kx,-ky))
    hk = iso2site(hktmp)
  end function hk_bhz_afm

  !--------------------------------------------------------------------!
  !PURPOSE: 
  !--------------------------------------------------------------------!
  function hk_bhz_afm8x8(kx,ky) result(hk)
    real(8)                     :: kx,ky
    complex(8),dimension(8,8)   :: hk
    hk(1,1:8)=[one*mh,zero,-one/2.d0,xi*lambda/2.d0,-one/2.d0,-one*lambda/2.d0,zero,zero]
    hk(2,1:8)=[zero,-one*mh,xi*lambda/2.d0,one/2.d0,one*lambda/2.d0,one/2.d0,zero,zero]
    hk(3,1:8)=[-one/2.d0,-xi*lambda/2.d0,one*mh,zero,zero,zero,-one/2.d0,-one*lambda/2.d0]
    hk(4,1:8)=[-xi*lambda/2.d0,one/2.d0,zero,-one*mh,zero,zero,one*lambda/2.d0,one/2.d0]
    hk(5,1:8)=[-one/2.d0,one*lambda/2.d0,zero,zero,one*mh,zero,-one/2.d0,xi*lambda/2.d0]
    hk(6,1:8)=[-one*lambda/2.d0,one/2.d0,zero,zero,zero,-one*mh,xi*lambda/2.d0,one/2.d0]
    hk(7,1:8)=[zero,zero,-one/2.d0,one*lambda/2.d0,-one/2.d0,-xi*lambda/2.d0,one*mh,zero]
    hk(8,1:8)=[zero,zero,-one*lambda/2.d0,one/2.d0,-xi*lambda/2.d0,one/2.d0,zero,-one*mh]
    !
    hk(1,1:8)=hk(1,1:8)+[zero,zero,exp(-xi*2.d0*kx)*(-0.5d0),exp(-xi*2.d0*kx)*(-xi*lambda/2.d0),exp(xi*2.d0*ky)*(-0.5d0),exp(xi*2.d0*ky)*(lambda/2.d0),zero,zero]
    hk(2,1:8)=hk(2,1:8)+[zero,zero,exp(-xi*2.d0*kx)*(-xi*lambda/2.d0),exp(-xi*2.d0*kx)*(0.5d0),exp(xi*2.d0*ky)*(-lambda/2.d0),exp(xi*2.d0*ky)*(0.5d0),zero,zero]
    hk(3,1:8)=hk(3,1:8)+[exp(xi*2.d0*kx)*(-0.5d0),exp(xi*2.d0*kx)*(xi*lambda/2.d0),zero,zero,zero,zero,exp(xi*2.d0*ky)*(-0.5d0),exp(xi*2.d0*ky)*(lambda/2.d0)]
    hk(4,1:8)=hk(4,1:8)+[exp(xi*2.d0*kx)*(xi*lambda/2.d0),exp(xi*2.d0*kx)*(0.5d0),zero,zero,zero,zero,exp(xi*2.d0*ky)*(-lambda/2.d0),exp(xi*2.d0*ky)*(0.5d0)]
    hk(5,1:8)=hk(5,1:8)+[exp(-xi*2.d0*ky)*(-0.5d0),exp(-xi*2.d0*ky)*(-lambda/2.d0),zero,zero,zero,zero,exp(-xi*2.d0*kx)*(-0.5d0),exp(-xi*2.d0*kx)*(-xi*lambda/2.d0)]
    hk(6,1:8)=hk(6,1:8)+[exp(-xi*2.d0*ky)*(lambda/2.d0),exp(-xi*2.d0*ky)*(0.5d0),zero,zero,zero,zero,exp(-xi*2.d0*kx)*(-xi*lambda/2.d0),exp(-xi*2.d0*kx)*(0.5d0)]
    hk(7,1:8)=hk(7,1:8)+[zero,zero,exp(-xi*2.d0*ky)*(-0.5d0),exp(-xi*2.d0*ky)*(-lambda/2.d0),exp(xi*2.d0*kx)*(-0.5d0),exp(xi*2.d0*kx)*(xi*lambda/2.d0),zero,zero]
    hk(8,1:8)=hk(8,1:8)+[zero,zero,exp(-xi*2.d0*ky)*(lambda/2.d0),exp(-xi*2.d0*ky)*(0.5d0),exp(xi*2.d0*kx)*(xi*lambda/2.d0),exp(xi*2.d0*kx)*(0.5d0),zero,zero]
  end function hk_bhz_afm8x8





  subroutine read_sigma(sigma)
    complex(8)        :: sigma(:,:,:,:,:,:)
    integer           :: iorb,ispin,i,L,unit
    real(8)           :: reS(Nspin),imS(Nspin),ww
    character(len=20) :: suffix
    if(size(sigma,1)/=Nindep)stop "read_sigma: error in dim 1. Nindep"
    if(size(sigma,2)/=Nspin)stop "read_sigma: error in dim 2. Nspin"
    if(size(sigma,4)/=Norb)stop "read_sigma: error in dim 4. Norb"
    L=size(sigma,6);print*,L
    if(L/=Lmats.AND.L/=Lreal)stop "read_sigma: error in dim 6. Lmats/Lreal"
    do ip=1,Nsites
       do iorb=1,Norb
          unit=free_unit()
          if(L==Lreal)then
             suffix="_l"//reg(txtfy(iorb))//"_m"//reg(txtfy(iorb))//"_realw_is"//reg(txtfy(ip))//".ed"
          elseif(L==Lmats)then
             suffix="_l"//reg(txtfy(iorb))//"_m"//reg(txtfy(iorb))//"_iw_is"//reg(txtfy(ip))//".ed"
          endif
          write(*,*)"read from file=","impSigma"//reg(suffix)
          open(unit,file="impSigma"//reg(suffix),status='old')
          do i=1,L
             read(unit,"(F26.15,6(F26.15))")ww,(imS(ispin),reS(ispin),ispin=1,Nspin)
             forall(ispin=1:Nspin)sigma(ip,ispin,ispin,iorb,iorb,i)=dcmplx(reS(ispin),imS(ispin))
          enddo
          close(unit)
       enddo
    enddo
    if(sitesym)then
       Sigma(4,:,:,:,:,:) = Sigma(1,:,:,:,:,:)
       Sigma(3,:,:,:,:,:) = Sigma(2,:,:,:,:,:)
    endif
    if(fullsym)then
       !step 1 extend the solution to ip=2 using the relations
       !A(ip=2,l,sigma) = A(ip=1,l,-sigma)
       do ispin=1,2
          Sigma(2,ispin,ispin,:,:,:)=Sigma(1,3-ispin,3-ispin,:,:,:)
       enddo
       !step 2 extend the solution to other ip=3,4
       Sigma(4,:,:,:,:,:) = Sigma(1,:,:,:,:,:)
       Sigma(3,:,:,:,:,:) = Sigma(2,:,:,:,:,:)
    endif
  end subroutine read_sigma





  !---------------------------------------------------------------------
  !PURPOSE: GET DELTA FUNCTION
  !---------------------------------------------------------------------
  subroutine get_delta
    integer                                       :: i,j,ik,iorb,jorb,ispin,jspin,iso,jso
    complex(8),dimension(Nindep,Nso,Nso)          :: zeta_site,fg_site,fgk_site
    complex(8),dimension(Nlso,Nlso)           :: zeta,fg,fgk
    complex(8),dimension(Nso,Nso)                 :: gdelta,self
    complex(8),dimension(:,:,:,:,:,:),allocatable :: gloc
    complex(8),dimension(:,:,:,:,:),allocatable   :: gk
    complex(8),dimension(:,:,:,:),allocatable     :: gfoo
    complex(8)                                    :: iw
    complex(8),dimension(Lmats,Nlso,Nlso)     :: gmats
    complex(8),dimension(Lreal,Nlso,Nlso)     :: greal
    real(8)                                       :: wm(Lmats),wr(Lreal),reS(Nspin),imS(Nspin),ww
    character(len=32)                             :: suffix
    integer :: unit
    !
    wm = pi/beta*real(2*arange(1,Lmats)-1,8)
    wr = linspace(wini,wfin,Lreal)
    delta=zero
    !MATSUBARA AXIS
    print*,"Get Gloc_iw:"
    allocate(gloc(Nindep,Nspin,Nspin,Norb,Norb,Lmats))
    do i=1,Lmats
       iw = xi*wm(i)
       zeta_site=zero
       do ip=1,Nindep
          forall(iso=1:Nso)zeta_site(ip,iso,iso)=iw+xmu
          zeta_site(ip,:,:) = zeta_site(ip,:,:)-so2j(Smats(ip,:,:,:,:,i))
       enddo
       zeta = blocks_to_matrix_(zeta_site)
       fg   = zero
       do ik=1,Lk
          fg = fg + inverse_gk(zeta,Hk(:,:,ik))*dos_wt(ik)
       enddo
       fg_site = matrix_to_blocks_(fg)
       do ip=1,Nindep
          gloc(ip,:,:,:,:,i) = j2so(fg_site(ip,:,:))
          call matrix_inverse(fg_site(ip,:,:)) !Get G_loc^{-1} used later
          !
          if(cg_scheme=='weiss')then
             gdelta = fg_site(ip,:,:) + so2j(Smats(ip,:,:,:,:,i))
             call matrix_inverse(gdelta)
          else
             gdelta = zeta_site(ip,:,:) - so2j(bhzHloc_site(ip)) - fg_site(ip,:,:)
          endif
          !
          delta(ip,:,:,:,:,i) = j2so(gdelta)
          !
       enddo

    enddo
    !PRINT
    do ip=1,Nsites
       do ispin=1,Nspin
          do iorb=1,Norb
             suffix="_is"//reg(txtfy(ip))//"_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_iw.ed"
             call splot("Delta"//reg(suffix),wm,delta(ip,ispin,ispin,iorb,iorb,:))
             call splot("Gloc"//reg(suffix),wm,gloc(ip,ispin,ispin,iorb,iorb,:))
          enddo
       enddo
    enddo
    deallocate(gloc)



    !REAL AXIS
    allocate(gloc(Nindep,Nspin,Nspin,Norb,Norb,Lreal))
    print*,"Get Gloc_realw:"
    do i=1,Lreal
       iw=dcmplx(wr(i),eps)
       zeta_site=zero
       do ip=1,Nindep
          forall(iso=1:Nso)zeta_site(ip,iso,iso)=iw+xmu
          zeta_site(ip,:,:) = zeta_site(ip,:,:)-so2j(Sreal(ip,:,:,:,:,i))
       enddo
       zeta = blocks_to_matrix_(zeta_site)
       fg   = zero
       do ik=1,Lk
          fg = fg + inverse_gk(zeta,Hk(:,:,ik))*dos_wt(ik)
       enddo
       fg_site = matrix_to_blocks_(fg)
       do ip=1,Nindep
          gloc(ip,:,:,:,:,i) = j2so(fg_site(ip,:,:))
       enddo
    enddo
    !PRINT
    do ip=1,Nsites
       do ispin=1,Nspin
          do iorb=1,Norb
             suffix="_is"//reg(txtfy(ip))//"_l"//reg(txtfy(iorb))//"_s"//reg(txtfy(ispin))//"_realw.ed"
             call splot("Gloc"//reg(suffix),wr,-dimag(gloc(ip,ispin,ispin,iorb,iorb,:))/pi,dreal(gloc(ip,ispin,ispin,iorb,iorb,:)))
          enddo
       enddo
    enddo
    deallocate(gloc)

  end subroutine get_delta






  !--------------------------------------------------------------------!
  !PURPOSE: 
  !--------------------------------------------------------------------!
  function inverse_gk(zeta,hk) result(gk)
    complex(8),dimension(16,16)   :: zeta,hk
    complex(8),dimension(16,16)   :: gk
    integer :: i
    ! gk=zeta-Hk
    gk = -Hk
    forall(i=1:Nlso)gk(i,i)=zeta(i,i) - hk(i,i)
    call matrix_inverse(gk)
  end function inverse_gk

  function inverse_g0k(zeta,hk,type) result(g0k)
    integer :: i
    complex(8)                  :: zeta
    complex(8),dimension(16,16) :: hk
    complex(8),dimension(16,16) :: g0k,g0ktmp
    integer,optional            :: type
    integer                     :: type_
    type_=0 ; if(present(type))type_=type
    if(type_==0)then
       g0k = -hk
       forall(i=1:16)g0k(i,i)=zeta - hk(i,i)
       call matrix_inverse(g0k)
    else
       g0k=zero
       g0k(1:8,1:8)   = inverse_g0k_8x8(zeta,hk(1:8,1:8))
       g0k(9:16,9:16) = inverse_g0k_8x8(zeta,hk(9:16,9:16))
    endif
  end function inverse_g0k

  function inverse_g0k_8x8(zeta,hk) result(g0k)
    complex(8)                :: zeta
    complex(8),dimension(8,8) :: hk
    complex(8),dimension(8,8) :: g0k
    integer :: i
    g0k = -hk
    forall(i=1:8)g0k(i,i)=zeta - hk(i,i)
    call matrix_inverse(g0k)
  end function inverse_g0k_8x8









  !--------------------------------------------------------------------!
  !TRANSFORMATION BETWEEN DIFFERENT BASIS:
  !--------------------------------------------------------------------!
  !--------------------------------------------------------------------!
  !PURPOSE: 
  !--------------------------------------------------------------------!
  function bhzHloc_site(isite) result(H)
    integer                              :: isite
    complex(8),dimension(Nindep,Nso,Nso) :: Vblocks
    complex(8)                           :: H(Nspin,Nspin,Norb,Norb)
    Vblocks = matrix_to_blocks_(bhzHloc)
    H = j2so(Vblocks(isite,:,:))
  end function bhzHloc_site


  !--------------------------------------------------------------------!
  !PURPOSE: 
  !--------------------------------------------------------------------!
  function blocks_to_matrix_(Vblocks) result(Matrix)
    complex(8),dimension(Nindep,Nso,Nso) :: Vblocks
    complex(8),dimension(Nlso,Nlso)  :: Matrix
    integer                              :: i,j,ip
    Matrix=zero
    do ip=1,Nindep
       i = (ip-1)*Nso + 1
       j = ip*Nso
       Matrix(i:j,i:j) =  Vblocks(ip,:,:)
    enddo
  end function blocks_to_matrix_


  !--------------------------------------------------------------------!
  !PURPOSE: 
  !--------------------------------------------------------------------!
  function matrix_to_blocks_(Matrix) result(Vblocks)
    complex(8),dimension(Nindep,Nso,Nso) :: Vblocks
    complex(8),dimension(Nlso,Nlso)  :: Matrix
    integer                                    :: i,j,ip
    Vblocks=zero
    do ip=1,Nindep
       i = (ip-1)*Nso + 1
       j = ip*Nso
       Vblocks(ip,:,:) = Matrix(i:j,i:j)
    enddo
  end function matrix_to_blocks_



  !--------------------------------------------------------------------!
  !PURPOSE: 
  !--------------------------------------------------------------------!
  function matrix_to_block(ip,Matrix) result(Vblock)
    complex(8),dimension(Nso,Nso) :: Vblock
    complex(8),dimension(Nlso,Nlso)  :: Matrix
    integer                              :: i,j,ip
    Vblock=zero
    i = (ip-1)*Nso + 1
    j = ip*Nso
    Vblock(:,:) = Matrix(i:j,i:j)
  end function matrix_to_block




  !--------------------------------------------------------------------!
  !PURPOSE: 
  !--------------------------------------------------------------------!
  function so2j_index(ispin,iorb) result(isporb)
    integer :: ispin,iorb
    integer :: isporb
    if(iorb>Norb)stop "error so2j_index: iorb>Norb"
    if(ispin>Nspin)stop "error so2j_index: ispin>Nspin"
    isporb=(ispin-1)*Nspin + iorb
  end function so2j_index

  !--------------------------------------------------------------------!
  !PURPOSE: 
  !--------------------------------------------------------------------!
  function so2j(fg) result(g)
    complex(8),dimension(Nspin,Nspin,Norb,Norb) :: fg
    complex(8),dimension(4,4)         :: g
    integer                                     :: i,j,iorb,jorb,ispin,jspin
    do ispin=1,Nspin
       do jspin=1,Nspin
          do iorb=1,Norb
             do jorb=1,Norb
                i=so2j_index(ispin,iorb)
                j=so2j_index(jspin,jorb)
                g(i,j) = fg(ispin,jspin,iorb,jorb)
             enddo
          enddo
       enddo
    enddo
  end function so2j


  !--------------------------------------------------------------------!
  !PURPOSE: 
  !--------------------------------------------------------------------!
  function j2so(fg) result(g)
    complex(8),dimension(Nso,Nso)         :: fg
    complex(8),dimension(Nspin,Nspin,Norb,Norb) :: g
    integer                                     :: i,j,iorb,jorb,ispin,jspin
    do ispin=1,Nspin
       do jspin=1,Nspin
          do iorb=1,Norb
             do jorb=1,Norb
                i=so2j_index(ispin,iorb)
                j=so2j_index(jspin,jorb)
                g(ispin,jspin,iorb,jorb)  = fg(i,j)
             enddo
          enddo
       enddo
    enddo
  end function j2so


  !--------------------------------------------------------------------!
  !PURPOSE: 
  !--------------------------------------------------------------------!
  function iso2site(hktmp) result(hk)
    complex(8),dimension(16,16) :: hktmp,hk
    integer                     :: icount,isite,ispin,iband,iorb
    integer                     :: jcount,jsite,jspin,jband,jorb
    integer                     :: row,col
    icount=0
    do isite=1,4
       do ispin=1,2
          do iorb=1,2
             icount=icount+1
             row = (ispin-1)*2*4 + (isite-1)*2 + iorb
             jcount=0
             do jsite=1,4
                do jspin=1,2
                   do jorb=1,2
                      jcount=jcount+1
                      col = (jspin-1)*2*4 + (jsite-1)*2 + jorb
                      hk(icount,jcount) = hktmp(row,col)
                   enddo
                enddo
             enddo
          enddo
       enddo
    enddo
  end function iso2site


  !--------------------------------------------------------------------!
  !PURPOSE: 
  !--------------------------------------------------------------------!
  function site2iso(hk) result(hktmp)
    complex(8),dimension(16,16) :: hktmp,hk
    integer                     :: icount,isite,ispin,iband,iorb
    integer                     :: jcount,jsite,jspin,jband,jorb
    integer                     :: row,col
    icount=0
    do isite=1,4
       do ispin=1,2
          do iorb=1,2
             icount=icount+1
             row = (ispin-1)*2*4 + (isite-1)*2 + iorb
             jcount=0
             do jsite=1,4
                do jspin=1,2
                   do jorb=1,2
                      jcount=jcount+1
                      col = (jspin-1)*2*4 + (jsite-1)*2 + jorb
                      hktmp(row,col) = hk(icount,jcount)
                   enddo
                enddo
             enddo
          enddo
       enddo
    enddo
  end function site2iso





end program ed_bhz_afm



