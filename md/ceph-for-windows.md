                     Ceph for Windows
               Cloudbase Solutions and SUSE
               Tech Preview:  June 27, 2020
   =====================================================

   Table of Contents

          Introduction
          Supported Platforms
          Compatibility
          Installation and Configuration
          RADOS Block Device (RBD)
            Mapping Images
            Hyper-V VM Disks
            Windows Partitions
          RBD Windows Service
          CephFS
          Appendix 1: Sample Configuration Files
          Appendix 2: Upstream Projects


Introduction
====================================
Ceph is a highly resilient software defined storage offering, which has only
been available to Windows environments through the use of iSCSI or CIFS
gateways. This gateway architecture introduces single points of contacts and
limits both fault tolerance and bandwidth - compared to the native I/O paths
of Ceph with RADOS.

In order to bring the benefits of native Ceph to Windows environments, SUSE
partnered with Cloudbase Solutions to port Ceph to the Windows platform.
This work is nearing completion, and provides the following functionality:

    RADOS Block Device (RBD)
    Cephfs

Additional information on the background on this effort can be found through
the following SUSECON Digital session:

   Ceph in a Windows World (TUT-1121)
   Presenters:
      Mike Latimer (SUSE)
      Alessandro Pilotti (Cloudbase Solutions)
   https://susecon20.mpeventapps.com/session-virtual/462/


Supported Platforms
===================

Windows Server 2019 and Windows Server 2016 are supported. Previous Windows
Server versions, including Windows client versions such as Windows 10, may
work but have not been thoroughly tested.

Early builds of Windows Server 2016 do not provide UNIX sockets, in which case
the Ceph admin socket feature will be unavailable.


Compatibility
=============

RBD images can be exposed to the OS and host Windows partitions or they can be
attached to Hyper-V VMs in the same way as iSCSI disks.

At the moment, the Microsoft Failover Cluster refuses to use WNBD disks as
Cluster Shared Volumes (CSVs) underlying storage.

OpenStack integration has been proposed as well and will most probably be
included in the next OpenStack release, allowing RBD images managed by OpenStack
Cinder to be attached to Hyper-V VMs managed by OpenStack Nova.


Installation and Configuration
====================================
Ceph for Windows can be easily installed through the Ceph.msi setup wizard.
This wizard performs the following functions:

  - Installs Ceph related code into C:\Program Files\Ceph
  - Adds C:\Program Files\Ceph\bin to the %PATH% environment variable
  - Creates a 'Ceph RBD Mapping Service' to automatically map RBD devices
    upon machine restart (using rbd-nbd.exe)

After installing Ceph for Windows, manual modifications are required to
provide access to a Ceph cluster. The files which must be created or modified
are as follows:

   C:\ProgramData\ceph\ceph.conf
   C:\ProgramData\ceph\ceph.client.admin.keyring

These files can be copied directly from an existing OSD node in the cluster.
Sample configuration files are also provided later in Appendix 1 of this
README file.


RADOS Block Device (RBD)
====================================
Support for RBD devices is now possible through a combination of Ceph tools
and a new Windows Network Block Device driver (WNBD). This driver is in the
process of being WHQL certified and signed by SUSE. (The Tech Preview version
is not yet signed, but will be available at a later date.)

Once installed, the 'WNBD SCSI Virtual Adapter' driver can be seen in Device
Manager as a Storage controller. Multiple adapters may be seen to handle
multiple number of RBD connections.

The 'rbd' command is used to create, remove, import, export, map or unmap
images exactly like it is used on Linux.

Mapping Images
-------------
The behavior of the 'rbd' command is similar to the Linux counterpart, with a
few notable differences:

* Device paths cannot be requested. The disk number and path will be picked by
  Windows. If a device path is provided by the user when mapping an image, it
  will be used as an identifier, which can also be used when unmapping the
  image.
* The 'show' command was added, which describes a specific mapping. This can be
  used for retrieving the disk path.
* The 'service' command was added, allowing rbd-nbd to run as a Windows service.
  All mappings are currently persistent, being recreated when the service
  stops, unless explicitly unmapped. The service disconnects the mappings
  when being stopped.
* The 'list' command also includes a 'status' column.

The mapped images can either be consumed by the host directly or exposed to
Hyper-V VMs.

Hyper-V VM Disks
~~~~~~~~~~~~~~~

The following sample imports an RBD image and boots a Hyper-V VM using it.

.. code:: PowerShell

    # Feel free to use any other image. This one is convenient to use for
    # testing purposes because it's very small (~15MB) and the login prompt
    # prints the pre-configured password.
    wget http://download.cirros-cloud.net/0.5.1/cirros-0.5.1-x86_64-disk.img `
         -OutFile cirros-0.5.1-x86_64-disk.img

    # We'll need to make sure that the imported images are raw (so no qcow2 or vhdx).
    # You may get qemu-img from https://cloudbase.it/qemu-img-windows/
    # You can add the extracted location to $env:Path or update the path accordingly.
    qemu-img convert -O raw cirros-0.5.1-x86_64-disk.img cirros-0.5.1-x86_64-disk.raw

    rbd import cirros-0.5.1-x86_64-disk.raw
    # Let's give it a hefty 100MB size.
    rbd resize cirros-0.5.1-x86_64-disk.raw --size=100MB

    rbd-nbd map cirros-0.5.1-x86_64-disk.raw

    # Let's have a look at the mappings.
    rbd-nbd list
    Get-Disk

    $mappingJson = rbd-nbd show cirros-0.5.1-x86_64-disk.raw --format=json
    $mappingJson = $mappingJson | ConvertFrom-Json

    $diskNumber = $mappingJson.disk_number

    New-VM -VMName BootFromRBD -MemoryStartupBytes 512MB
    # The disk must be turned offline before it can be passed to Hyper-V VMs
    Set-Disk -Number $diskNumber -IsOffline $true
    Add-VMHardDiskDrive -VMName BootFromRBD -DiskNumber $diskNumber
    Start-VM -VMName BootFromRBD

Windows Partitions
~~~~~~~~~~~~~~~~~

The following sample creates an empty RBD image, attaches it to the host and
initializes a partition.

.. code:: PowerShell

    rbd create blank_image --size=1G
    rbd-nbd map blank_image

    $mappingJson = rbd-nbd show blank_image --format=json
    $mappingJson = $mappingJson | ConvertFrom-Json

    $diskNumber = $mappingJson.disk_number

    # The disk must be online before creating or accessing partitions.
    Set-Disk -Number $diskNumber -IsOffline $false

    # Initialize the disk, partition it and create a fileystem.
    Get-Disk -Number $diskNumber | `
        Initialize-Disk -PassThru | `
        New-Partition -AssignDriveLetter -UseMaximumSize | `
        Format-Volume -Force -Confirm:$false


RBD Windows service
====================================
In order to ensure that rbd-nbd mappings survive host reboots, a new Windows
service, called "Ceph RBD Mapping Service", has been created. This service
automatically maintains mappings as they are added using the Ceph tools. All
mappings are currently persistent, being recreated when the service starts,
unless explicitly unmapped.  The service disconnects all mappings when being
stopped.

This service also adjust the Windows service start order so that rbd images
can be mapped before starting services that may depend on it, such as
VMMS.

RBD maps are stored in the Windows registry at the following location:

    SYSTEM\CurrentControlSet\Services\rbd-nbd


CephFS
====================================
Ceph for Windows provides CephFS support through the Dokany FUSE wrapper.
In order to use CephFS, please install Dokany v1.3.1 or newer, which can
be found at the following URL:

        https://github.com/dokan-dev/dokany/releases

With Dokany installed, and the ceph.conf and ceph.client.admin.keyring
configuration files in place, CephFS can be mounted using the ceph-dokan.exe
commands, as in the following example:

    ceph-dokan.exe -l x

The above command will mount the default ceph filesystem using the drive
letter 'x'. If 'ceph.conf' is not placed at the default location (which
is 'C:\ProgramData\ceph\ceph.conf', a '-c' parameter can be used to specify
the location of ceph.conf.

The '-l' argument also allows using an empty folder as a mountpoint instead
of a drive letter.

The uid and gid used for mounting the filesystem defaults to 0 and may be
changed using the '-u' and '-g' arguments. '-n' can be used in order to skip
enforcing permissions on client side. Be aware that Windows ACLs are ignored.
Posix ACLs are supported but cannot be modified using the current CLI. In the
future, we may add some command actions to change file ownership or permissions.

For debugging purposes, '-d' and 's' may be used. The first one enables debug
output and the latter enables stderr logging. By default, debug messages are
sent to a connected debugger.

You may use '--help' to get the full list of available options.   



Appendix 1: Sample Configuration Files
===================================

C:\ProgramData\ceph\ceph.conf
-----------------
[global]
     log to stderr = true
     run dir = C:/ProgramData/ceph/out
     crash dir = C:/ProgramData/ceph/out
[client]
     keyring = C:/ProgramData/ceph/keyring
     log file = C:/ProgramData/ceph/out/$name.$pid.log
     admin socket = C:/ProgramData/ceph/out/$name.$pid.asok
[global]
     ; Specify IP addresses for monitor nodes as in the following example:
     ; mon host =  [v2:10.1.1.1:3300,v1:10.1.1.1:6789] [v2:10.1.1.2:3300,v1:10.1.1.2:6789] [v2:10.1.1.3:3300,v1:1.1.1.3:6789]


C:\ProgramData\ceph\ceph.client.admin.keyring
-----------------
; This file should be copied directly from /etc/ceph/ceph.client.admin.keyring
; The contents should be similar to the following example:
[client.admin]
        key = ADCyl77eBBAAABDDjX72tAljOwv04m121v/7yA==
        caps mds = "allow *"
        caps mon = "allow *"
        caps osd = "allow *"
        caps mgr = "allow *"


Appendix 2: Upstream Projects
===================================
The Ceph for Windows effort is being done entire in Open Source, and in
conjunction with the upstream project(s). For more development level details,
feel free to join the discussion in the following projects:

  Ceph:  https://github.com/ceph/ceph/pull/34859
  WNBD:  https://github.com/cloudbase/wnbd
  Installer:  https://github.com/cloudbase/ceph-windows-installer


