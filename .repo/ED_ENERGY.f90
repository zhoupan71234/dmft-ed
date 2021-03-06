!########################################################################
!purpose  : Obtain some physical quantities and print them out
!########################################################################
MODULE ED_ENERGY
  USE ED_INPUT_VARS
  USE ED_VARS_GLOBAL
  ! USE ED_EIGENSPACE
  USE ED_SETUP
  USE ED_AUX_FUNX
  ! USE ED_MATVEC
  !
  USE ED_MPI2B
  !
  USE SF_CONSTANTS, only:zero,pi,xi
  USE SF_IOTOOLS, only:free_unit,reg,txtfy
  USE SF_ARRAYS, only: arange
  USE SF_TIMER
  USE SF_LINALG, only: inv,eye,zeye,eigh,diag
  USE SF_MISC,  only:assert_shape
  USE SF_SPECIAL, only:fermi
  implicit none
  private


  interface ed_kinetic_energy
     module procedure kinetic_energy_impurity_normal_main
     module procedure kinetic_energy_impurity_normal_1B
     module procedure kinetic_energy_impurity_normal_MB
     module procedure kinetic_energy_lattice_normal_main
     module procedure kinetic_energy_lattice_normal_1
     module procedure kinetic_energy_lattice_normal_1B     


     module procedure kinetic_energy_impurity_superc_main
     module procedure kinetic_energy_impurity_superc_1B
     module procedure kinetic_energy_impurity_superc_MB
     module procedure kinetic_energy_lattice_superc_main
     module procedure kinetic_energy_lattice_superc_1
     module procedure kinetic_energy_lattice_superc_1B
     ! end interface ed_kinetic_energy

     ! interface ed_kinetic_energy_lattice
  end interface ed_kinetic_energy

  !PUBLIC in DMFT
  public :: ed_kinetic_energy
  ! public :: ed_kinetic_energy_lattice


  real(8),dimension(:),allocatable        :: wm

contains 




  !-------------------------------------------------------------------------------------------
  !PURPOSE: Evaluate the Kinetic energy for the lattice model, given 
  ! the Hamiltonian matrix H(k) and the DMFT self-energy NORMAL Sigma.
  ! The main routine accept self-energy as:
  ! - Sigma: [Nspin*Norb][Nspin*Norb][L]
  ! - Sigma: [L]
  ! - Sigma: [Nspin][Nspin][Norb][Norb][L]
  !-------------------------------------------------------------------------------------------
  !> Sigma [Nspin*Norb][Nspin*Norb][L]
  function kinetic_energy_impurity_normal_main(Hk,Wtk,Sigma) result(Eout)
    complex(8),dimension(:,:,:)                 :: Hk ![Nspin*Norb][Nspin*Norb][Lk]
    complex(8),dimension(:,:,:)                 :: Sigma !
    real(8),dimension(size(Hk,3))               :: Wtk   ![Lk]
    integer                                     :: Lk,Nso,Liw
    integer                                     :: i,ik
    !
    real(8),dimension(size(Hk,1),size(Hk,1))    :: Sigma_HF
    complex(8),dimension(size(Hk,1),size(Hk,1)) :: Ak,Bk,Ck,Dk,Hloc
    complex(8),dimension(size(Hk,1),size(Hk,1)) :: Gk,Tk
    real(8)                                     :: Tail0,Tail1,Lail0,Lail1,spin_degeneracy
    !
    real(8)                                     :: H0,Hl,ed_Ekin,ed_Eloc
    real(8)                                     :: Eout(2)
    !
    Nso = size(Hk,1)
    Lk  = size(Hk,3)
    Liw = size(Sigma,3)
    call assert_shape(Hk,[Nso,Nso,Lk],"kinetic_energy_impurity_normal_main","Hk")
    call assert_shape(Sigma,[Nso,Nso,Liw],"kinetic_energy_impurity_normal_main","Sigma")
    !
    if(allocated(wm))deallocate(wm);allocate(wm(Liw))
    !
    wm = pi/beta*dble(2*arange(1,Liw)-1)
    !
    Sigma_HF = dreal(Sigma(:,:,Liw))
    !
    Hloc = sum(Hk(:,:,:),dim=3)/Lk
    where(abs(dreal(Hloc))<1.d-9)Hloc=0d0
    if(ED_MPI_ID==0)then
       if(size(Hloc,1)<16)then
          call print_hloc(Hloc)
       else
          call print_hloc(Hloc,"Hloc_kin"//reg(ed_file_suffix)//".ed")
       endif
    endif
    !
    if(ED_MPI_ID==0)call start_timer()
    H0=0d0
    Hl=0d0
    do ik=1,Lk
       Ak = Hk(:,:,ik) - Hloc(:,:)
       Bk =-Hk(:,:,ik) - Sigma_HF(:,:)
       do i=1,Liw
          Gk = (xi*wm(i)+xmu)*eye(Nso) - Sigma(:,:,i) - Hk(:,:,ik) 
          select case(Nso)
          case default
             call inv(Gk)
          case(1)
             Gk = 1d0/Gk
          end select
          Tk = eye(Nso)/(xi*wm(i)) - Bk(:,:)/(xi*wm(i))**2
          Ck = matmul(Ak  ,Gk - Tk)
          Dk = matmul(Hloc,Gk - Tk)
          H0 = H0 + Wtk(ik)*trace_matrix(Ck,Nso)
          Hl = Hl + Wtk(ik)*trace_matrix(Dk,Nso)
       enddo
       if(ED_MPI_ID==0)call eta(ik,Lk)
    enddo
    if(ED_MPI_ID==0)call stop_timer()
    spin_degeneracy=3.d0-Nspin !2 if Nspin=1, 1 if Nspin=2
    H0=H0/beta*2.d0*spin_degeneracy
    Hl=Hl/beta*2.d0*spin_degeneracy
    !
    Tail0=0d0
    Tail1=0d0
    Lail0=0d0
    Lail1=0d0
    do ik=1,Lk
       Ak    = Hk(:,:,ik) - Hloc(:,:)
       Ck= matmul(Ak,(-Hk(:,:,ik)-Sigma_HF(:,:)))
       Dk= matmul(Hloc,(-Hk(:,:,ik)-Sigma_HF(:,:)))
       Tail0 = Tail0 + 0.5d0*Wtk(ik)*trace_matrix(Ak,Nso)
       Tail1 = Tail1 + 0.25d0*Wtk(ik)*trace_matrix(Ck,Nso)
       Lail0 = Lail0 + 0.5d0*Wtk(ik)*trace_matrix(Hloc(:,:),Nso)
       Lail1 = Lail1 + 0.25d0*Wtk(ik)*trace_matrix(Dk,Nso)
    enddo
    Tail0=spin_degeneracy*Tail0
    Tail1=spin_degeneracy*Tail1*beta
    Lail0=spin_degeneracy*Lail0
    Lail1=spin_degeneracy*Lail1*beta
    ed_Ekin=H0+Tail0+Tail1
    ed_Eloc=Hl+Lail0+Lail1
    Eout = [ed_Ekin,ed_Eloc]
    deallocate(wm)
    if(ED_MPI_ID==0)then
       call write_kinetic_info()
       call write_kinetic(Eout)
    endif
  end function kinetic_energy_impurity_normal_main
  !
  !> Sigma [Nspin][Nspin][Norb][Norb][L]
  function kinetic_energy_impurity_normal_MB(Hk,Wtk,Sigma) result(Eout)
    complex(8),dimension(:,:,:)             :: Hk
    real(8),dimension(size(Hk,3))           :: Wtk
    complex(8),dimension(:,:,:,:,:)         :: Sigma ![Nspin][Nspin][Norb][Norb][Lmats]
    complex(8),dimension(:,:,:),allocatable :: Sigma_
    integer                                 :: Nspin,Norb,Lmats,Nso,i,iorb,jorb,ispin,jspin,io,jo
    real(8),dimension(2)                    :: Eout
    !
    Nspin = size(Sigma,1)
    Norb  = size(Sigma,3)
    Lmats = size(Sigma,5)
    Nso   = Nspin*Norb
    call assert_shape(Sigma,[Nspin,Nspin,Norb,Norb,Lmats],"kinetic_energy_impurity_normal_MB","Sigma")
    allocate(Sigma_(Nso,Nso,Lmats))
    do i=1,Lmats
       Sigma_(:,:,i) = nn2so_reshape(Sigma(:,:,:,:,i),Nspin,Norb)
    enddo
    Eout = kinetic_energy_impurity_normal_main(Hk,Wtk,Sigma_)
  end function kinetic_energy_impurity_normal_MB
  !
  !> Sigma [L]
  function kinetic_energy_impurity_normal_1B(Hk,Wtk,Sigma) result(Eout)
    complex(8),dimension(:)               :: Sigma
    complex(8),dimension(:)               :: Hk
    real(8),dimension(size(Hk))           :: Wtk
    complex(8),dimension(1,1,size(Sigma)) :: Sigma_
    complex(8),dimension(1,1,size(Hk))    :: Hk_
    real(8),dimension(2)                  :: Eout
    Sigma_(1,1,:) = Sigma
    Hk_(1,1,:)    = Hk
    Eout = kinetic_energy_impurity_normal_main(Hk_,Wtk,Sigma_)
  end function kinetic_energy_impurity_normal_1B
















  !-------------------------------------------------------------------------------------------
  !PURPOSE: Evaluate the Kinetic energy for the lattice case SUPERCONDUCTING, given 
  ! the Hamiltonian matrix Hk and the DMFT self-energy Sigma.
  ! The main routine accept self-energy as
  !-------------------------------------------------------------------------------------------
  !
  ! > Sigma [Nspin*Norb][Nspin*Norb][L]
  ! > Self  [Nspin*Norb][Nspin*Norb][L]
  function kinetic_energy_impurity_superc_main(Hk,Wtk,Sigma,Self) result(Eout)
    integer                                         :: Lk,Nso,Liw
    integer                                         :: i,is,ik
    complex(8),dimension(:,:,:)                     :: Hk
    complex(8),dimension(:,:,:)                     :: Sigma,Self
    real(8),dimension(size(Hk,3))                   :: Wtk
    real(8),dimension(size(Hk,1),size(Hk,1))        :: Sigma_HF,Self_HF
    complex(8),dimension(size(Hk,1),size(Hk,1))     :: Ak,Bk,Ck,Hloc
    complex(8),dimension(size(Hk,1),size(Hk,1))     :: Gk,Tk
    complex(8),dimension(2*size(Hk,1),2*size(Hk,1)) :: GkNambu,HkNambu,HlocNambu,AkNambu
    real(8),dimension(2*size(Hk,1))                 :: NkNambu
    complex(8),dimension(2*size(Hk,1),2*size(Hk,1)) :: Evec
    real(8),dimension(2*size(Hk,1))                 :: Eval,Coef
    real(8)                                         :: spin_degeneracy
    real(8)                                         :: H0,Hl,H0free,Hlfree,ed_Ekin,ed_Eloc,H0tmp
    real(8)                                         :: Eout(2)
    !
    Nso = size(Hk,1)
    Lk  = size(Hk,3)
    Liw = size(Sigma,3)
    call assert_shape(Hk,[Nso,Nso,Lk],"kinetic_energy_impurity_superc_main","Hk")
    call assert_shape(Sigma,[Nso,Nso,Liw],"kinetic_energy_impurity_superc_main","Sigma")
    call assert_shape(Self,[Nso,Nso,Liw],"kinetic_energy_impurity_superc_main","Self")
    !
    if(allocated(wm))deallocate(wm);allocate(wm(Liw))
    wm = pi/beta*dble(2*arange(1,Liw)-1)
    !
    ! Get the local Hamiltonian, i.e. the block diagonal part of the full Hk summed over k
    Hloc = sum(Hk(:,:,:),dim=3)/Lk
    where(abs(dreal(Hloc))<1.d-9)Hloc=0d0
    if(ED_MPI_ID==0)then
       if(size(Hloc,1)<16)then
          call print_hloc(Hloc)
       else
          call print_hloc(Hloc,"Hloc_kin"//reg(ed_file_suffix)//".ed")
       endif
    endif
    !
    !Get HF part of the self-energy
    Sigma_HF = dreal(Sigma(:,:,Liw))
    Self_HF  = dreal(Self(:,:,Liw))
    !
    if(ED_MPI_ID==0) write(LOGfile,*) "Kinetic energy computation"
    if(ED_MPI_ID==0)call start_timer
    H0=0d0
    Hl=0d0
    do ik=1,Lk
       Ak= Hk(:,:,ik)-Hloc
       do i=1,Liw
          Gknambu=zero
          Gknambu(1:Nso,1:Nso)             = (xi*wm(i) + xmu)*eye(Nso)  - Sigma(:,:,i)        - Hk(:,:,ik)
          Gknambu(1:Nso,Nso+1:2*Nso)       =                            - Self(:,:,i)
          Gknambu(Nso+1:2*Nso,1:Nso)       =                            - Self(:,:,i)
          Gknambu(Nso+1:2*Nso,Nso+1:2*Nso) = (xi*wm(i) - xmu)*eye(Nso)  + conjg(Sigma(:,:,i)) + Hk(:,:,ik)
          call inv(Gknambu)
          Gk  = Gknambu(1:Nso,1:Nso) !Gk(iw)
          !
          Gknambu=zero
          Gknambu(1:Nso,1:Nso)             = (xi*wm(i) + xmu)*eye(Nso)  - Sigma_hf  - Hk(:,:,ik)
          Gknambu(1:Nso,Nso+1:2*Nso)       =                            - Self_hf
          Gknambu(Nso+1:2*Nso,1:Nso)       =                            - Self_hf
          Gknambu(Nso+1:2*Nso,Nso+1:2*Nso) = (xi*wm(i) - xmu)*eye(Nso)  + Sigma_hf  + Hk(:,:,ik)
          call inv(Gknambu)
          Tk = Gknambu(1:Nso,1:Nso) !G0k(iw)
          !
          Bk = matmul(Ak, Gk - Tk) !
          H0 = H0 + Wtk(ik)*trace_matrix(Bk,Nso)
          Ck = matmul(Hloc,Gk - Tk)
          Hl = Hl + Wtk(ik)*trace_matrix(Ck,Nso)
       enddo
       if(ED_MPI_ID==0)call eta(ik,Lk,unit=LOGfile)
    enddo
    if(ED_MPI_ID==0)call stop_timer
    spin_degeneracy=3d0-dble(Nspin) !2 if Nspin=1, 1 if Nspin=2
    H0=H0/beta*2.d0*spin_degeneracy
    Hl=Hl/beta*2.d0*spin_degeneracy
    !
    !
    H0free=0d0
    Hlfree=0d0
    HkNambu=zero
    HlocNambu=zero
    do ik=1,Lk
       HkNambu(1:Nso,1:Nso)               =  Hk(:,:,ik)-Hloc
       HkNambu(Nso+1:2*Nso,Nso+1:2*Nso)   = -Hk(:,:,ik)+Hloc
       HlocNambu(1:Nso,1:Nso)             =  Hloc
       HlocNambu(Nso+1:2*Nso,Nso+1:2*Nso) = -Hloc
       Evec(1:Nso,1:Nso)                 =  Hk(:,:,ik) + Sigma_hf
       Evec(1:Nso,Nso+1:2*Nso)           =             + Self_hf
       Evec(Nso+1:2*Nso,1:Nso)           =             + Self_hf
       Evec(Nso+1:2*Nso,Nso+1:2*Nso)     = -Hk(:,:,ik) - Sigma_hf
       call eigh(Evec,Eval)
       do is=1,2*Nso
          Coef = Evec(:,is)*conjg(Evec(:,is))
          NkNambu(is) = dot_product(Coef,fermi(Eval,beta))
       enddo
       AkNambu = matmul( diag(NkNambu) , HkNambu )
       H0free = H0free + Wtk(ik)*trace_matrix(AkNambu(:Nso,:Nso),Nso) !Take only the 11 part
       AkNambu = matmul( diag(NkNambu) , HlocNambu )
       Hlfree = Hlfree + Wtk(ik)*trace_matrix(AkNambu(:Nso,:Nso),Nso)
    enddo
    H0free=spin_degeneracy*H0free
    Hlfree=spin_degeneracy*Hlfree
    ! !<DEBUG 2*Nlso bug
    ! print*,"ED_ENERGY Efree0:",H0free
    ! print*,"ED_ENERGY Efreel:",Hlfree
    ! print*,"ED_ENERGY Total :",H0free+Hlfree
    ! !>DEBUG
    ed_Ekin=H0+H0free
    ed_Eloc=Hl+Hlfree
    deallocate(wm)
    Eout = [ed_Ekin,ed_Eloc]
    if(ED_MPI_ID==0)then
       call write_kinetic_info()
       call write_kinetic(Eout)
    endif
  end function kinetic_energy_impurity_superc_main
  !
  !> Sigma  [Nspin][Nspin][Norb][Norb][L]
  !> SigmaA [Nspin][Nspin][Norb][Norb][L]
  function kinetic_energy_impurity_superc_MB(Hk,Wtk,Sigma,Self) result(Eout)
    complex(8),dimension(:,:,:)             :: Hk
    real(8),dimension(size(Hk,3))           :: Wtk
    complex(8),dimension(:,:,:,:,:)         :: Sigma
    complex(8),dimension(:,:,:,:,:)         :: Self
    complex(8),dimension(:,:,:),allocatable :: Sigma_
    complex(8),dimension(:,:,:),allocatable :: Self_
    integer                                 :: Nspin,Norb,Lmats,Nso,i,iorb,jorb,ispin,jspin,io,jo
    real(8)                                 :: Eout(2)
    Nspin = size(Sigma,1)
    Norb  = size(Sigma,3)
    Lmats = size(Sigma,5)
    Nso   = Nspin*Norb
    call assert_shape(Sigma,[Nspin,Nspin,Norb,Norb,Lmats],"kinetic_energy_impurity_superc_MB","Sigma")
    call assert_shape(Self,[Nspin,Nspin,Norb,Norb,Lmats],"kinetic_energy_impurity_superc_MB","Self")    
    allocate(Sigma_(Nso,Nso,Lmats))
    allocate(Self_(Nso,Nso,Lmats))
    do i=1,Lmats
       Sigma_(:,:,i) = nn2so_reshape(Sigma(:,:,:,:,i),Nspin,Norb)
       Self_(:,:,i)  = nn2so_reshape(Self(:,:,:,:,i),Nspin,Norb)
    enddo
    Eout = kinetic_energy_impurity_superc_main(Hk,Wtk,Sigma_,Self_)
  end function kinetic_energy_impurity_superc_MB
  !
  !> Sigma  [L]
  !> SigmaA [L]
  function kinetic_energy_impurity_superc_1B(Hk,Wtk,Sigma,Self) result(Eout)
    real(8),dimension(:)                  :: Hk
    real(8),dimension(size(Hk))           :: Wtk
    complex(8),dimension(:)               :: Sigma
    complex(8),dimension(size(Sigma))     :: Self
    complex(8),dimension(1,1,size(Sigma)) :: Sigma_
    complex(8),dimension(1,1,size(Sigma)) :: Self_
    complex(8),dimension(1,1,size(Hk))    :: Hk_
    real(8)                               :: Eout(2)
    Sigma_(1,1,:)  = Sigma(:)
    Self_(1,1,:)   = Self(:)
    Hk_(1,1,:)     = Hk
    Eout = kinetic_energy_impurity_superc_main(Hk_,Wtk,Sigma_,Self_)
  end function kinetic_energy_impurity_superc_1B


















  !-------------------------------------------------------------------------------------------
  !PURPOSE: Evaluate the Kinetic energy for the general lattice case, given 
  ! the Hamiltonian matrix Hk and the DMFT self-energy Sigma.
  ! The main routine accept:
  !-------------------------------------------------------------------------------------------
  !
  !> Sigma [Nlat][Nspin*Norb][Nspin*Norb][L]
  function kinetic_energy_lattice_normal_main(Hk,Wtk,Sigma) result(Eout)
    complex(8),dimension(:,:,:)                                     :: Hk        ! [Nlat*Nspin*Norb][Nlat*Nspin*Norb][Nk]
    real(8),dimension(size(Hk,3))                                   :: wtk       ! [Nk]
    complex(8),dimension(:,:,:,:)                                   :: Sigma     ! [Nlat][Nspin*Norb][Nspin*Norb][L]
    !aux
    integer                                                         :: Lk,Nlso,Liw,Nlat,Nso
    integer                                                         :: ik
    integer                                                         :: i,iorb,ilat,ispin,io,is
    integer                                                         :: j,jorb,jlat,jspin,jo,js
    complex(8),dimension(size(Sigma,1),size(Sigma,2),size(Sigma,3)) :: Sigma_HF
    complex(8),dimension(size(Hk,1),size(Hk,1))                     :: Ak,Bk,Ck,Dk,Hloc,Hloc_tmp
    complex(8),dimension(size(Hk,1),size(Hk,1))                     :: Tk
    complex(8),dimension(size(Hk,1),size(Hk,1))                     :: Gk
    real(8)                                                         :: Tail0,Tail1,Lail0,Lail1,spin_degeneracy
    !
    real(8)                                                         :: H0,H0k,H0ktmp,Hl,Hlk,Hlktmp
    real(8)                                                         :: ed_Ekin_lattice,ed_Eloc_lattice
    real(8)                                                         :: Eout(2)
    !
    Nlso = size(Hk,1)
    Lk   = size(Hk,3)
    Nlat = size(Sigma,1)
    Nso  = size(Sigma,2)
    Liw  = size(Sigma,4)
    call assert_shape(Hk,[Nlat*Nso,Nlso,Lk],"kinetic_energy_lattice_normal_main","Hk") !implcitly test that Nlat*Nso=Nlso
    call assert_shape(Sigma,[Nlat,Nso,Nso,Liw],"kinetic_energy_lattice_normal_main","Sigma")
    !
    !Allocate and setup the Matsubara freq.
    if(allocated(wm))deallocate(wm);allocate(wm(Liw))
    wm = pi/beta*(2*arange(1,Liw)-1)
    !
    ! Get the local Hamiltonian, i.e. the block diagonal part of the full Hk summed over k
    Hloc_tmp=sum(Hk(:,:,:),dim=3)/dble(Lk)
    Hloc=0.d0
    do ilat=1,Nlat
       do ispin=1,Nspin
          do jspin=1,Nspin
             do iorb=1,Norb
                do jorb=1,Norb
                   is = iorb + (ispin-1)*Norb + (ilat-1)*Nspin*Norb
                   js = jorb + (jspin-1)*Norb + (ilat-1)*Nspin*Norb
                   Hloc(is,js)=Hloc_tmp(is,js) 
                enddo
             enddo
          enddo
       enddo
    enddo
    !
    where(abs(dreal(Hloc))<1.d-9)Hloc=0d0
    if(ED_MPI_MASTER)then
       if(size(Hloc,1)<16)then
          call print_hloc(Hloc)
       else
          call print_hloc(Hloc,"Hloc_kin"//reg(ed_file_suffix)//".ed")
       endif
    endif
    !
    !Get HF part of the self-energy
    Sigma_HF(:,:,:) = dreal(Sigma(:,:,:,Liw))
    !
    !Start the timer:
    if(ED_MPI_MASTER) write(LOGfile,*) "Kinetic energy computation"
    if(ED_MPI_MASTER)call start_timer
    ed_Ekin_lattice = 0d0
    ed_Eloc_lattice = 0d0
    H0              = 0d0
    Hl              = 0d0
    !Get principal part: Tr[ Hk.(Gk-Tk) ]
    do ik=1,Lk
       Ak    =  Hk(:,:,ik) - Hloc(:,:)
       Bk    = -Hk(:,:,ik) - blocks_to_matrix(Sigma_HF(:,:,:)) !Sigma_HF [Nlat,Nso,Nso]--> [Nlso,Nslo]
       H0ktmp= 0d0
       Hlktmp= 0d0
       H0k   = 0d0
       Hlk   = 0d0
       do i=1+ED_MPI_ID,Lmats,ED_MPI_SIZE
          Gk = (xi*wm(i)+xmu)*eye(Nlso) - blocks_to_matrix(Sigma(:,:,:,i)) - Hk(:,:,ik) !Sigma [Nlat,Nso,Nso,*]--> [Nlso,Nslo]
          call inv(Gk(:,:))
          Tk = zeye(Nlso)/(xi*wm(i)) - Bk/(xi*wm(i))**2
          Ck = matmul(Ak,Gk(:,:) - Tk)
          Dk = matmul(Hloc,Gk(:,:) - Tk)
          H0ktmp = H0ktmp + Wtk(ik)*trace_matrix(Ck,Nlso)
          Hlktmp = Hlktmp + Wtk(ik)*trace_matrix(Dk,Nlso)
       enddo
#ifdef _MPI
       call MPI_ALLREDUCE(H0ktmp,H0k,1,MPI_DOUBLE_PRECISION,MPI_SUM,ED_MPI_COMM,ED_MPI_ERR)
       call MPI_ALLREDUCE(Hlktmp,Hlk,1,MPI_DOUBLE_PRECISION,MPI_SUM,ED_MPI_COMM,ED_MPI_ERR)
#else
       H0k=H0ktmp
       Hlk=Hlktmp
#endif
       H0 = H0 + H0k
       Hl = Hl + Hlk
       if(ED_MPI_MASTER)call eta(ik,Lk,unit=LOGfile)
    enddo
    if(ED_MPI_MASTER)call stop_timer
    spin_degeneracy=3.d0-Nspin !2 if Nspin=1, 1 if Nspin=2
    H0 = H0/beta*2d0*spin_degeneracy
    Hl = Hl/beta*2d0*spin_degeneracy
    !
    !get tail subtracted contribution: Tr[ Hk.Tk ]
    Tail0=0d0
    Tail1=0d0
    Lail0=0d0
    Lail1=0d0
    do ik=1,Lk
       Ak    =  Hk(:,:,ik) - Hloc(:,:)
       Bk    = -Hk(:,:,ik) - blocks_to_matrix(Sigma_HF(:,:,:)) !Sigma_HF [Nlat,Nso,Nso]--> [Nlso,Nslo]
       Ck= matmul(Ak,Bk)
       Dk= matmul(Hloc,Bk)
       Tail0 = Tail0 + 0.5d0*Wtk(ik)*trace_matrix(Ak,Nlso)
       Tail1 = Tail1 + 0.25d0*Wtk(ik)*trace_matrix(Ck,Nlso)
       Lail0 = Lail0 + 0.5d0*Wtk(ik)*trace_matrix(Hloc(:,:),Nlso)
       Lail1 = Lail1 + 0.25d0*Wtk(ik)*trace_matrix(Dk,Nlso)
    enddo
    Tail0=spin_degeneracy*Tail0
    Tail1=spin_degeneracy*Tail1*beta
    Lail0=spin_degeneracy*Lail0
    Lail1=spin_degeneracy*Lail1*beta
    ed_Ekin_lattice=H0+Tail0+Tail1
    ed_Eloc_lattice=Hl+Lail0+Lail1
    ed_Ekin_lattice=ed_Ekin_lattice/dble(Nlat)
    ed_Eloc_lattice=ed_Eloc_lattice/dble(Nlat)
    Eout = [ed_Ekin_lattice,ed_Eloc_lattice]
    deallocate(wm)
    if(ED_MPI_MASTER)then
       call write_kinetic_info()
       call write_kinetic(Eout)
    endif
  end function kinetic_energy_lattice_normal_main
  !
  !> Sigma [Nlat][Nspin][Nspin][Norb][Norb][L]
  function kinetic_energy_lattice_normal_1(Hk,Wtk,Sigma) result(ed_Ekin_lattice)
    complex(8),dimension(:,:,:)                               :: Hk     ! [Nlat*Nspin*Norb][Nlat*Nspin*Norb][Nk]
    real(8),dimension(size(Hk,3))                             :: wtk    ! [Nk]
    complex(8),dimension(:,:,:,:,:,:)                         :: Sigma  ! [Nlat][Nspin][Nspin][Norb][Norb][L]
    complex(8),dimension(:,:,:,:),allocatable                 :: Sigma_ ! [Nlat][Nspin*Norb][Nspin*Norb][L]
    integer                                                   :: ilat,jlat,iorb,jorb,ispin,jspin,io,jo,is,js
    integer                                                   :: Nlat,Nspin,Norb,Nlso,Nso,Lk,Liw
    real(8)                                                   :: ed_Ekin_lattice(2)
    !Get generalized Lattice-Spin-Orbital index
    Nlat = size(Sigma,1)
    Nspin= size(Sigma,2)
    Norb = size(Sigma,4)
    Nso  = Nspin*Norb
    Nlso = size(Hk,1)
    Liw  = size(Sigma,6)
    Lk   = size(Hk,3)
    Nlso = Nlat*Nspin*Norb
    call assert_shape(Hk,[Nlso,Nlso,Lk],"kinetic_energy_lattice_normal_2","Hk")
    call assert_shape(Sigma,[Nlat,Nspin,Nspin,Norb,Norb,Liw],"kinetic_energy_lattice_normal_2","Sigma")
    allocate(Sigma_(Nlat,Nso,Nso,Liw))
    Sigma_ = zero
    do ispin=1,Nspin
       do jspin=1,Nspin
          do iorb=1,Norb
             do jorb=1,Norb
                io = iorb + (ispin-1)*Norb
                jo = jorb + (jspin-1)*Norb
                Sigma_(:,io,jo,:) = Sigma(:,ispin,jspin,iorb,jorb,:)
             enddo
          enddo
       enddo
    enddo
    ed_Ekin_lattice = kinetic_energy_lattice_normal_main(Hk,Wtk,Sigma_)
  end function kinetic_energy_lattice_normal_1
  !
  !> Sigma [Nlat][L]
  function kinetic_energy_lattice_normal_1B(Hk,Wtk,Sigma) result(ed_Ekin_lattice)
    complex(8),dimension(:,:,:)                               :: Hk     ! [Nlat*Nspin*Norb][Nlat*Nspin*Norb][Nk]
    real(8),dimension(size(Hk,3))                             :: wtk    ! [Nk]
    complex(8),dimension(:,:)                                 :: Sigma  ! [Nlat][L]
    complex(8),dimension(:,:,:,:),allocatable                 :: Sigma_ ! [Nlat][Nspin*Norb][Nspin*Norb][L]
    integer                                                   :: ilat
    integer                                                   :: Nlat,Nlso,Nso,Lk
    real(8)                                                   :: ed_Ekin_lattice(2)
    Nlat = size(Sigma,1)
    Nlso = size(Hk,1)
    Lk   = size(Hk,3)
    call assert_shape(Hk,[Nlat,Nlso,Lk],"kinetic_energy_lattice_normal_1B","Hk") !implictly test Nlat*1*=Nlso
    allocate(Sigma_(Nlat,1,1,size(Sigma,2)))
    Sigma_(:,1,1,:) = Sigma(:,:)
    ed_Ekin_lattice = kinetic_energy_lattice_normal_main(Hk,Wtk,Sigma_)
  end function kinetic_energy_lattice_normal_1B






















  !-------------------------------------------------------------------------------------------
  !PURPOSE: Evaluate the Kinetic energy for the general lattice case, given 
  ! the Hamiltonian matrix Hk and the DMFT self-energy Sigma.
  !-------------------------------------------------------------------------------------------
  !> Sigma [Nlat][Nspin*Norb][Nspin*Norb][L]
  !> Self  [Nlat][Nspin*Norb][Nspin*Norb][L]
  function kinetic_energy_lattice_superc_main(Hk,Wtk,Sigma,Self) result(Eout)
    complex(8),dimension(:,:,:)                                     :: Hk     ! [Nlat*Nspin*Norb][Nlat*Nspin*Norb][Nk]
    real(8),dimension(size(Hk,3))                                   :: wtk    ! [Nk]
    complex(8),dimension(:,:,:,:)                                   :: Sigma  ! [Nlat][Nspin*Norb][Nspin*Norb][L]
    complex(8),dimension(:,:,:,:)                                   :: Self   ! [Nlat][Nspin*Norb][Nspin*Norb][L]  
    integer                                                         :: Lk,Nlso,Liw,Nso
    integer                                                         :: ik
    integer                                                         :: i,iorb,ilat,ispin,io,is
    integer                                                         :: j,jorb,jlat,jspin,jo,js
    complex(8),dimension(size(Sigma,1),size(Sigma,2),size(Sigma,3)) :: Sigma_HF ![Nlat][Nso][Nso]
    complex(8),dimension(size(Sigma,1),size(Sigma,2),size(Sigma,3)) :: Self_HF  ![Nlat][Nso][Nso]
    complex(8),dimension(size(Hk,1),size(Hk,2))                     :: Ak,Bk,Ck,Hloc,Hloc_tmp
    complex(8),dimension(size(Hk,1),size(Hk,2))                     :: Gk,Tk
    complex(8),dimension(2*size(Hk,1),2*size(Hk,2))                 :: Gknambu,HkNambu,HlocNambu,AkNambu
    real(8),dimension(2*size(Hk,1))                                 :: NkNambu
    complex(8),dimension(2*size(Hk,1),2*size(Hk,2))                 :: Evec
    real(8),dimension(2*size(Hk,1))                                 :: Eval,Coef
    real(8)                                                         :: spin_degeneracy
    !
    real(8)                                                         :: H0,Hl
    real(8)                                                         :: H0free,Hlfree
    real(8)                                                         :: H0k,Hlk
    real(8)                                                         :: H0ktmp,Hlktmp
    real(8)                                                         :: ed_Ekin_lattice,ed_Eloc_lattice
    real(8)                                                         :: Eout(2)
    !Get generalized Lattice-Spin-Orbital index
    Nlso = size(Hk,1)
    Lk   = size(Hk,3)
    Nlat = size(Sigma,1)
    Nso  = size(Sigma,2)
    Liw  = size(Sigma,4)
    call assert_shape(Hk,[Nlat*Nso,Nlso,Lk],"kinetic_energy_lattice_superc_main","Hk") !implcitly test that Nlat*Nso=Nlso
    call assert_shape(Sigma,[Nlat,Nso,Nso,Liw],"kinetic_energy_lattice_superc_main","Sigma")
    call assert_shape(Self,[Nlat,Nso,Nso,Liw],"kinetic_energy_lattice_superc_main","Self")
    !
    !Allocate and setup the Matsubara freq.
    if(allocated(wm))deallocate(wm);allocate(wm(Liw))
    wm = pi/beta*(2*arange(1,Liw)-1)
    !
    ! Get the local Hamiltonian, i.e. the block diagonal part of the full Hk summed over k
    Hloc_tmp=sum(Hk(:,:,:),dim=3)/dble(Lk)
    Hloc=zero
    do ilat=1,Nlat
       do ispin=1,Nspin
          do jspin=1,Nspin
             do iorb=1,Norb
                do jorb=1,Norb
                   is = iorb + (ispin-1)*Norb + (ilat-1)*Nspin*Norb
                   js = jorb + (jspin-1)*Norb + (ilat-1)*Nspin*Norb
                   Hloc(is,js)=Hloc_tmp(is,js) 
                enddo
             enddo
          enddo
       enddo
    enddo
    where(abs(dreal(Hloc))<1.d-9)Hloc=0d0
    if(ED_MPI_MASTER)then
       if(size(Hloc,1)<16)then
          call print_hloc(Hloc)
       else
          call print_hloc(Hloc,"Hloc_kin"//reg(ed_file_suffix)//".ed")
       endif
    endif
    !
    !Get HF part of the self-energy
    Sigma_HF = dreal(Sigma(:,:,:,Liw))![Nlat,Nso,Nso]
    Self_HF  = dreal(Self(:,:,:,Liw)) ![Nlat,Nso,Nso]
    !
    !Start the timer:
    if(ED_MPI_MASTER) write(LOGfile,*) "Kinetic energy computation"
    if(ED_MPI_MASTER)call start_timer
    ed_Ekin_lattice = 0d0
    ed_Eloc_lattice = 0d0
    H0              = 0d0
    Hl              = 0d0
    !Get principal part: Tr[ Hk.(Gk-Tk) ]
    do ik=1,Lk
       Ak    = Hk(:,:,ik) - Hloc(:,:)
       H0ktmp= 0d0
       H0k   = 0d0
       Hlktmp= 0d0
       Hlk   = 0d0
       !
       do i=1+ED_MPI_ID,Lmats,ED_MPI_SIZE
          Gknambu=zero
          Gknambu(1:Nlso,1:Nlso)               = (xi*wm(i) + xmu)*eye(Nlso) -       blocks_to_matrix(Sigma(:,:,:,i))  - Hk(:,:,ik)
          Gknambu(1:Nlso,Nlso+1:2*Nlso)        =                            -       blocks_to_matrix(Self(:,:,:,i))
          Gknambu(Nlso+1:2*Nlso,1:Nlso)        =                            -       blocks_to_matrix(Self(:,:,:,i))
          Gknambu(Nlso+1:2*Nlso,Nlso+1:2*Nlso) = (xi*wm(i) - xmu)*eye(Nlso) + conjg(blocks_to_matrix(Sigma(:,:,:,i))) + Hk(:,:,ik)
          call inv(Gknambu(:,:))
          Gk = Gknambu(1:Nlso,1:Nlso)
          !
          Gknambu=zero
          Gknambu(1:Nlso,1:Nlso)               = (xi*wm(i) + xmu)*eye(Nlso) -       blocks_to_matrix(Sigma_HF)  - Hk(:,:,ik)
          Gknambu(1:Nlso,Nlso+1:2*Nlso)        =                            -       blocks_to_matrix(Self_HF)
          Gknambu(Nlso+1:2*Nlso,1:Nlso)        =                            -       blocks_to_matrix(Self_HF)
          Gknambu(Nlso+1:2*Nlso,Nlso+1:2*Nlso) = (xi*wm(i) - xmu)*eye(Nlso) +       blocks_to_matrix(Sigma_HF)  + Hk(:,:,ik)
          call inv(Gknambu(:,:))
          Tk = Gknambu(1:Nlso,1:Nlso)
          !
          Bk = matmul(Ak, Gk - Tk)
          H0ktmp = H0ktmp + Wtk(ik)*trace_matrix(Bk,Nlso)
          Ck = matmul(Hloc, Gk - Tk)
          Hlktmp = Hlktmp + Wtk(ik)*trace_matrix(Ck,Nlso)
       enddo
#ifdef _MPI
       call MPI_ALLREDUCE(H0ktmp,H0k,1,MPI_DOUBLE_PRECISION,MPI_SUM,ED_MPI_COMM,ED_MPI_ERR)
       call MPI_ALLREDUCE(Hlktmp,Hlk,1,MPI_DOUBLE_PRECISION,MPI_SUM,ED_MPI_COMM,ED_MPI_ERR)
#else
       H0k = H0ktmp
       Hlk = Hlktmp
#endif
       H0 = H0 + H0k
       Hl = Hl + Hlk
       if(ED_MPI_MASTER)call eta(ik,Lk,unit=LOGfile)
    enddo
    if(ED_MPI_MASTER)call stop_timer
    spin_degeneracy=3.d0-dble(Nspin) !2 if Nspin=1, 1 if Nspin=2
    H0 = H0/beta*2d0*spin_degeneracy;print*,"Ekin_=",H0/Nlat
    Hl = Hl/beta*2d0*spin_degeneracy;print*,"Eloc_=",Hl/Nlat
    !
    !
    !get tail subtracted contribution: Tr[ Hk.Tk ]
    H0free=0d0
    Hlfree=0d0
    HkNambu=zero
    HlocNambu=zero
    do ik=1,Lk
       HkNambu(1:Nlso,1:Nlso)                 =  Hk(:,:,ik)-Hloc
       HkNambu(Nlso+1:2*Nlso,Nlso+1:2*Nlso)   = -Hk(:,:,ik)+Hloc
       HlocNambu(1:Nlso,1:Nlso)               =  Hloc
       HlocNambu(Nlso+1:2*Nlso,Nlso+1:2*Nlso) = -Hloc
       Evec(1:Nlso,1:Nlso)                    =  Hk(:,:,ik) +  blocks_to_matrix(Sigma_HF)
       Evec(1:Nlso,Nlso+1:2*Nlso)             =             +  blocks_to_matrix(Self_HF)
       Evec(Nlso+1:2*Nlso,1:Nlso)             =             +  blocks_to_matrix(Self_HF)
       Evec(Nlso+1:2*Nlso,Nlso+1:2*Nlso)      = -Hk(:,:,ik) -  blocks_to_matrix(Sigma_HF)
       call eigh(Evec,Eval)
       NkNambu = fermi(Eval,beta)
       GkNambu = matmul(Evec,matmul(diag(NkNambu),conjg(transpose(Evec))))
       AkNambu = matmul(HkNambu  , GkNambu)
       H0free  = H0free + Wtk(ik)*trace_matrix( AkNambu(:Nlso,:Nlso) , Nlso) !take only the 11 part
       AkNambu = matmul(HlocNambu, GkNambu)
       Hlfree  = Hlfree + Wtk(ik)*trace_matrix( AkNambu(:Nlso,:Nlso) , Nlso)

    enddo
    H0free=spin_degeneracy*H0free;print*,"Efree=",H0free/Nlat
    Hlfree=spin_degeneracy*Hlfree;print*,"Efree_loc=",Hlfree/Nlat
    !
    ed_Ekin_lattice=H0+H0free
    ed_Eloc_lattice=Hl+Hlfree
    !
    ed_Ekin_lattice=ed_Ekin_lattice/dble(Nlat)
    ed_Eloc_lattice=ed_Eloc_lattice/dble(Nlat)
    Eout = [ed_Ekin_lattice,ed_Eloc_lattice]
    deallocate(wm)
    if(ED_MPI_MASTER)then
       call write_kinetic_info()
       call write_kinetic(Eout)
    endif
  end function kinetic_energy_lattice_superc_main


  !> Sigma [Nlat][Nspin][Nspin][Norb][Norb][L]
  !> Self  [Nlat][Nspin][Nspin][Norb][Norb][L]
  function kinetic_energy_lattice_superc_1(Hk,Wtk,Sigma,Self) result(ed_Ekin_lattice)
    complex(8),dimension(:,:,:)               :: Hk     ! [Nlat*Nspin*Norb][Nlat*Nspin*Norb][Nk]
    real(8),dimension(size(Hk,3))             :: wtk    ! [Nk]
    complex(8),dimension(:,:,:,:,:,:)         :: Sigma  ! [Nlat][Nspin][Nspin][Norb][Norb][L]
    complex(8),dimension(:,:,:,:,:,:)         :: Self ! [Nlat][Nspin][Nspin][Norb][Norb][L]
    complex(8),dimension(:,:,:,:),allocatable :: Sigma_ 
    complex(8),dimension(:,:,:,:),allocatable :: Self_
    integer                                   :: i,iorb,ilat,ispin,io,is
    integer                                   :: j,jorb,jlat,jspin,jo,js
    integer                                   :: Nlat,Nspin,Norb,Nlso,Nso,Lk,Liw
    real(8)                                   :: ed_Ekin_lattice(2)
    !Get generalized Lattice-Spin-Orbital index
    Nlat = size(Sigma,1)
    Nspin= size(Sigma,2)
    Norb = size(Sigma,4)
    Nso  = Nspin*Norb
    Nlso = size(Hk,1)
    Liw  = size(Sigma,6)
    Lk   = size(Hk,3)
    !Nlso = Nlat*Nspin*Norb
    call assert_shape(Hk,[Nlat*Nso,Nlso,Lk],"kinetic_energy_lattice_superc_2","Hk") !implictly check Nlat*Nso=Nlso
    call assert_shape(Sigma,[Nlat,Nspin,Nspin,Norb,Norb,Liw],"kinetic_energy_lattice_superc_2","Sigma")
    call assert_shape(Self,[Nlat,Nspin,Nspin,Norb,Norb,Liw],"kinetic_energy_lattice_superc_2","Self")
    allocate(Sigma_(Nlat,Nso,Nso,Liw))
    allocate(Self_(Nlat,Nso,Nso,Liw))
    Sigma_=zero
    Self_=zero
    do ispin=1,Nspin
       do jspin=1,Nspin
          do iorb=1,Norb
             do jorb=1,Norb
                is = iorb + (ispin-1)*Norb  !spin-orbit stride
                js = jorb + (jspin-1)*Norb  !spin-orbit stride
                Sigma_(:,is,js,:) =  Sigma(:,ispin,jspin,iorb,jorb,:)
                Self_(:,is,js,:)= Self(:,ispin,jspin,iorb,jorb,:)
             enddo
          enddo
       enddo
    enddo
    ed_Ekin_lattice = kinetic_energy_lattice_superc_main(Hk,Wtk,Sigma_,Self_)
  end function kinetic_energy_lattice_superc_1
  !> Sigma [Nlat][L]
  !> Self  [Nlat][L]
  function kinetic_energy_lattice_superc_1B(Hk,Wtk,Sigma,Self) result(ed_Ekin_lattice)
    complex(8),dimension(:,:,:)                       :: Hk     ! [Nlat*Nspin*Norb][Nlat*Nspin*Norb][Nk]
    real(8),dimension(size(Hk,3))                     :: wtk    ! [Nk]
    complex(8),dimension(:,:)                         :: Sigma  ! [Nlat][L]
    complex(8),dimension(size(Sigma,1),size(Sigma,2)) :: Self ! [Nlat][L]  
    complex(8),dimension(:,:,:,:),allocatable         :: Sigma_ 
    complex(8),dimension(:,:,:,:),allocatable         :: Self_
    integer                                           :: i,iorb,ilat,ispin,io,is
    integer                                           :: j,jorb,jlat,jspin,jo,js
    integer                                           :: Nlat,Nlso,Nso,Lk,Liw
    real(8)                                           :: ed_Ekin_lattice(2)
    Nlat = size(Sigma,1)
    Liw  = size(Sigma,2)
    Nlso = size(Hk,1)
    Lk   = size(Hk,3)
    call assert_shape(Hk,[Nlat,Nlso,Lk],"kinetic_energy_lattice_superc_1B","Hk") !implictly test Nlat*1*1=Nlso
    allocate(Sigma_(Nlat,1,1,Liw))
    allocate(Self_(Nlat,1,1,Liw))
    Sigma_(:,1,1,:)  = Sigma
    Self_(:,1,1,:) = Self
    ed_Ekin_lattice = kinetic_energy_lattice_superc_main(Hk,Wtk,Sigma_,Self_)
  end function kinetic_energy_lattice_superc_1B












  !####################################################################
  !                    COMPUTATIONAL ROUTINES
  !####################################################################
  function trace_matrix(M,dim) result(tr)
    integer                       :: dim
    complex(8),dimension(dim,dim) :: M
    complex(8)                    :: tr
    integer                       :: i
    tr=dcmplx(0d0,0d0)
    do i=1,dim
       tr=tr+M(i,i)
    enddo
  end function trace_matrix


  !+-------------------------------------------------------------------+
  !PURPOSE  : write legend, i.e. info about columns 
  !+-------------------------------------------------------------------+
  subroutine write_kinetic_info()
    integer :: unit
    unit = free_unit()
    open(unit,file="kinetic_info.ed")
    write(unit,"(A1,90(A14,1X))")"#",reg(txtfy(1))//"<K>",reg(txtfy(2))//"<Eloc>"
    close(unit)
  end subroutine write_kinetic_info



  !+-------------------------------------------------------------------+
  !PURPOSE  : Write energies to file
  !+-------------------------------------------------------------------+
  subroutine write_kinetic(Ekin)
    real(8) :: Ekin(2)
    integer :: unit
    unit = free_unit()
    open(unit,file="kinetic_last"//reg(ed_file_suffix)//".ed")
    write(unit,"(90F15.9)")Ekin(1),Ekin(2)
    close(unit)
  end subroutine write_kinetic


end MODULE ED_ENERGY







! function kinetic_energy_impurity_superc_main(Hk,Wtk,Sigma,Self) result(Eout)
!   integer                                         :: Lk,Nso,Liw
!   integer                                         :: i,ik,iorb,jorb,inambu,jnambu,n,m
!   complex(8),dimension(:,:,:)                     :: Hk
!   complex(8),dimension(:,:,:)                     :: Sigma,Self
!   real(8),dimension(size(Hk,3))                   :: Wtk
!   !
!   real(8),dimension(size(Hk,1),size(Hk,1))        :: Sigma_HF,Self_HF
!   complex(8),dimension(size(Hk,1),size(Hk,1))     :: Ak,Bk,Ck,Dk,Hloc
!   complex(8),dimension(size(Hk,1),size(Hk,1))     :: Gk,Tk
!   complex(8),dimension(2*size(Hk,1),2*size(Hk,1)) :: Gk_Nambu
!   complex(8),dimension(2,2)                       :: Gk_Nambu_ij
!   !
!   real(8)                                         :: Tail0,Tail1,Lail0,Lail1,spin_degeneracy
!   !
!   real(8)                                         :: H0,Hl,ed_Ekin,ed_Eloc
!   real(8)                                         :: Eout(2)
!   !
!   Nso = size(Hk,1)
!   Lk  = size(Hk,3)
!   Liw = size(Sigma,3)
!   call assert_shape(Hk,[Nso,Nso,Lk],"kinetic_energy_impurity_superc_main","Hk")
!   call assert_shape(Sigma,[Nso,Nso,Liw],"kinetic_energy_impurity_superc_main","Sigma")
!   call assert_shape(Self,[Nso,Nso,Liw],"kinetic_energy_impurity_superc_main","Self")
!   !
!   if(allocated(wm))deallocate(wm);allocate(wm(Liw))
!   !
!   wm = pi/beta*dble(2*arange(1,Liw)-1)
!   !
!   Sigma_HF = dreal(Sigma(:,:,Liw))
!   !    
!   Hloc = sum(Hk(:,:,:),dim=3)/Lk
!   where(abs(dreal(Hloc))<1.d-9)Hloc=0d0
!   if(ED_MPI_MASTER.AND.size(Hloc,1)<64)call print_hloc(Hloc)
!   !
!   H0=0d0
!   do ik=1,Lk
!      Ak= Hk(:,:,ik)-Hloc
!      Bk=-Hk(:,:,ik)-Sigma_HF(:,:)
!      do i=1,Liw
!         Gk=zero      
!         !> I know you are tempted to rationalize this below: just do not do it. It works. Do not touch it!!
!         do iorb=1,Nso
!            do jorb=1,Nso
!               Gk_Nambu_ij=zero
!               Gk_Nambu_ij(1,1) =  -Hk(iorb,jorb,ik) - Sigma(iorb,jorb,i)
!               Gk_Nambu_ij(1,2) =                    - Self(iorb,jorb,i)
!               Gk_Nambu_ij(2,1) =                    - Self(iorb,jorb,i)
!               Gk_Nambu_ij(2,2) =   Hk(iorb,jorb,ik) + conjg(Sigma(iorb,jorb,i))!-conjg(Gk_Nambu_ij(1,1))
!               if(iorb==jorb) then
!                  Gk_Nambu_ij(1,1) = Gk_Nambu_ij(1,1) + xi*wm(i) + xmu
!                  Gk_Nambu_ij(2,2) = Gk_Nambu_ij(1,1) + xi*wm(i) - xmu
!               end if
!               do inambu=1,2
!                  do jnambu=1,2
!                     m=(inambu-1)*Nso + iorb
!                     n=(jnambu-1)*Nso + jorb
!                     Gk_nambu(m,n)=Gk_nambu_ij(inambu,jnambu)
!                  enddo
!               enddo
!            enddo
!         enddo
!         call inv(Gk_Nambu)
!         inambu=1
!         jnambu=1
!         do iorb=1,Nso
!            do jorb=1,Nso
!               m=(inambu-1)*Nso + iorb
!               n=(jnambu-1)*Nso + jorb
!               Gk(iorb,jorb) =  Gk_Nambu(m,n)
!            enddo
!         enddo
!         Tk = eye(Nso)/(xi*wm(i)) - Bk(:,:)/(xi*wm(i))**2
!         Ck = matmul(Ak,Gk - Tk)
!         Dk = matmul(Hloc,Gk - Tk)
!         H0 = H0 + Wtk(ik)*trace_matrix(Ck,Nso)
!         Hl = Hl + Wtk(ik)*trace_matrix(Dk,Nso)
!      enddo
!   enddo
!   spin_degeneracy=3.d0-Nspin !2 if Nspin=1, 1 if Nspin=2
!   H0=H0/beta*2.d0*spin_degeneracy
!   Hl=Hl/beta*2.d0*spin_degeneracy          
!   !
!   Tail0=0d0
!   Tail1=0d0
!   Lail0=0d0
!   Lail1=0d0
!   do ik=1,Lk
!      Ak    = Hk(:,:,ik) - Hloc(:,:)
!      Ck= matmul(Ak,(-Hk(:,:,ik)-Sigma_HF(:,:)))
!      Dk= matmul(Hloc,(-Hk(:,:,ik)-Sigma_HF(:,:)))
!      Tail0 = Tail0 + 0.5d0*Wtk(ik)*trace_matrix(Ak,Nso)
!      Tail1 = Tail1 + 0.25d0*Wtk(ik)*trace_matrix(Ck,Nso)
!      Lail0 = Lail0 + 0.5d0*Wtk(ik)*trace_matrix(Hloc,Nso)
!      Lail1 = Lail1 + 0.25d0*Wtk(ik)*trace_matrix(Dk,Nso)
!   enddo
!   Tail0=spin_degeneracy*Tail0
!   Tail1=spin_degeneracy*Tail1*beta
!   Lail0=spin_degeneracy*Lail0
!   Lail1=spin_degeneracy*Lail1*beta
!   ed_Ekin=H0+Tail0+Tail1
!   ed_Eloc=Hl+Lail0+Lail1
!   deallocate(wm)
!   Eout = [ed_Ekin,ed_Eloc]
!   call write_kinetic_info()
!   call write_kinetic(Eout)
! end function kinetic_energy_impurity_superc_main
