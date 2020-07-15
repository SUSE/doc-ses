.. _deploy-cephadm:

Deploying with cephadm
======================

cephadm deploys and manages a Ceph cluster by connecting to hosts from
the Ceph Manager daemon via SSH. cephadm manages the full lifecycle of a
Ceph cluster. It starts by bootstrapping a tiny cluster on a single node
(one MON and MGR service) and then uses the orchestration interface to
expand the cluster to include all hosts and to provision all Ceph
services. You can perform this via the Ceph command line interface (CLI)
or Ceph Dashboard (GUI).

To deploy a Ceph cluster by using cephadm, you need to complete the
following tasks:

1. Install and do basic configuration of the underlying operating
   system—SUSE Linux Enterprise Server 15 SP2—on all cluster nodes.

2. Deploy the Salt infrastructure over all cluster nodes so that you can
   orchestrate them effectively.

3. Configure the basic properties of the cluster and deploy it.

4. Add new nodes to the cluster and deploy services to them.

.. _deploy-os:

Install and Configure SUSE Linux Enterprise Server
==================================================

1. Install and register SUSE Linux Enterprise Server 15 SP2 on each
   cluster node. Include at least the following modules:

   -  Basesystem Module

   -  Server Applications Module

   Find more details on how to install SUSE Linux Enterprise Server in
   https://documentation.suse.com/sles/15-SP2/html/SLES-all/cha-install.html.

2. Install the *SUSE Enterprise Storage 7* extension on each cluster
   node.

      **Tip**

      You can either install the SUSE Enterprise Storage 7 extension
      separately after you have installed SUSE Linux Enterprise Server
      15 SP2, or you can add it during the SUSE Linux Enterprise Server
      15 SP2 installation procedure.

   Find more details on how to install extensions in
   https://documentation.suse.com/sles/15-SP2/html/SLES-all/cha-register-sle.html.

3. Configure network settings including proper DNS name resolution on
   each node. For more information on configuring a network, see
   https://documentation.suse.com/sles/15-SP2/single-html/SLES-admin/#sec-network-yast
   For more information on configuring a DNS server, see
   https://documentation.suse.com/sles/15-SP2/single-html/SLES-admin/#cha-dns.

Deploy Salt
===========

SUSE Enterprise Storage uses Salt as a cluster orchestrator. Salt helps
you configure and run commands on multiple cluster nodes simultaneously
from one dedicated host called the *Salt Master*. Before deploying Salt,
consider the following important points:

-  *Salt Minions* are the nodes controlled by a dedicated node called
   Salt Master. Salt Minions have roles, for example Ceph OSD, Ceph
   Monitor, Ceph Manager, Object Gateway, iSCSI Gateway, or NFS Ganesha.

-  A Salt Master runs its own Salt Minion. It is required for running
   privileged tasks—for example creating, authorizing, and copying keys
   to minions—so that remote minions never need to run privileged tasks.

      **Tip**

      You will get the best performance from your Ceph cluster when each
      role is deployed on a separate node. But real deployments
      sometimes require sharing one node for multiple roles. To avoid
      trouble with performance and the upgrade procedure, do not deploy
      the Ceph OSD, Metadata Server, or Ceph Monitor role to the Admin
      Node.

-  Salt Minions need to correctly resolve the Salt Master's host name
   over the network. By default, they look for the salt host name, but
   you can specify any other network-reachable host name in the
   ``/etc/salt/minion`` file.

1. Install the ``salt-master`` and ``salt-minion`` packages on the Salt
   Master node:

   ::

      root@master # zypper in salt-master salt-minion

   Check that the salt-master service is enabled and started, and enable
   and start it if needed:

   ::

      root@master # systemctl enable salt-master.service
      root@master # systemctl start salt-master.service

2. If you intend to use the firewall, verify that the Salt Master node
   has ports 4505 and 4506 open to all Salt Minion nodes. If the ports
   are closed, you can open them using the ``yast2 firewall`` command by
   allowing the SaltStack service.

3. Install the package ``salt-minion`` on all minion nodes.

   ::

      root@minion > zypper in salt-minion

   Make sure that the *fully qualified domain name* of each node can be
   resolved to an IP address on the public cluster network by all the
   other nodes.

4. Configure all minions (including the master minion) to connect to the
   master. If your Salt Master is not reachable by the host name
   ``salt``, edit the file ``/etc/salt/minion`` or create a new file
   ``/etc/salt/minion.d/master.conf`` with the following content:

   ::

      master: host_name_of_salt_master

   If you performed any changes to the configuration files mentioned
   above, restart the Salt service on all related Salt Minions:

   ::

      root@minion > systemctl restart salt-minion.service

5. Check that the salt-minion service is enabled and started on all
   nodes. Enable and start it if needed:

   ::

      root # systemctl enable salt-minion.service
      root # systemctl start salt-minion.service

6. Verify each Salt Minion's fingerprint and accept all salt keys on the
   Salt Master if the fingerprints match.

      **Note**

      If the Salt Minion fingerprint comes back empty, make sure the
      Salt Minion has a Salt Master configuration and that it can
      communicate with the Salt Master.

   View each minion's fingerprint:

   ::

      root@minion > salt-call --local key.finger
      local:
      3f:a3:2f:3f:b4:d3:d9:24:49:ca:6b:2c:e1:6c:3f:c3:83:37:f0:aa:87:42:e8:ff...

   After gathering fingerprints of all the Salt Minions, list
   fingerprints of all unaccepted minion keys on the Salt Master:

   ::

      root@master # salt-key -F
      [...]
      Unaccepted Keys:
      minion1:
      3f:a3:2f:3f:b4:d3:d9:24:49:ca:6b:2c:e1:6c:3f:c3:83:37:f0:aa:87:42:e8:ff...

   If the minions' fingerprints match, accept them:

   ::

      root@master # salt-key --accept-all

7. Verify that the keys have been accepted:

   ::

      root@master # salt-key --list-all

8. Test whether all Salt Minions respond:

   ::

      root@master # salt '*' test.ping

.. _deploy-cephadm-day1:

Deploy Basic Cluster (Day 1)
============================

This section guides you through the process of deploying a basic Ceph
cluster. Read the following subsections carefully and execute the
included commands in the given order.

.. _deploy-cephadm-cephsalt:

Install ceph-salt
-----------------

ceph-salt provides tools for deploying Ceph clusters managed by cephadm.
ceph-salt uses the Salt infrastructure to perform OS management—for
example, software updates or time synchronization—and defining roles for
Salt Minions.

On the Salt Master, install the ceph-salt package:

::

   root@master # zypper install ceph-salt

The above command installed ceph-salt-formula as a dependency which
modified the Salt Master configuration by inserting additional files in
the ``/etc/salt/master.d`` directory. To apply the changes, restart
salt-master.service and synchronize Salt modules:

::

   root@master # systemctl restart salt-master.service
   root@master # salt \* saltutil.sync_all

.. _deploy-cephadm-configure:

Configure Cluster Properties
----------------------------

Use the ``ceph-salt config`` command to configure the basic properties
of the cluster.

.. _deploy-cephadm-configure-shell:

ceph-salt Shell
~~~~~~~~~~~~~~~

If you run ``ceph-salt config`` without any path or subcommand, you will
enter an interactive ceph-salt shell. The shell is convenient if you
need to configure multiple properties in one batch and do not want type
the full command syntax.

::

   root@master # ceph-salt config
   /> ls
   o- / ............................................................... [...]
     o- ceph_cluster .................................................. [...]
     | o- minions .............................................. [no minions]
     | o- roles ....................................................... [...]
     |   o- admin .............................................. [no minions]
     |   o- bootstrap ........................................... [no minion]
     |   o- cephadm ............................................ [no minions]
     o- cephadm_bootstrap ............................................. [...]
     | o- advanced .................................................... [...]
     | o- ceph_conf ................................................... [...]
     | o- dashboard ................................................... [...]
     |   o- password ................................... [randomly generated]
     |   o- username ................................................ [admin]
     | o- mon_ip ............................................. [10.100.25.51]
     o- containers .................................................... [...]
     | o- images ...................................................... [...]
     |   o- ceph ............................................ [no image path]
     | o- registries ................................................ [empty]
     o- ssh ............................................... [no key pair set]
     | o- private_key .................................. [no private key set]
     | o- public_key .................................... [no public key set]
     o- system_update ................................................. [...]
     | o- packages ................................................ [enabled]
     | o- reboot .................................................. [enabled]
     o- time_server ............................................... [enabled]
       o- external_servers .......................................... [empty]
       o- server_hostname ......................................... [not set]
       o- subnet .................................................. [not set]

As you can see from the output of ceph-salt's ``ls`` command, the
cluster configuration is organized in a tree structure. To configure a
specific property of the cluster in the ceph-salt shell, you have two
options:

-  Change to the path whose property you need to configure and run the
   command:

   ::

      /> cd /ceph_cluster/minions/
      /ceph_cluster/minions> ls
      o- minions .................................................. [Minions: 5]
        o- ses-master.example.com ................................... [no roles]
        o- ses-min1.example.com ..................................... [no roles]
      [...]

-  Run the command from the current position and enter the absolute path
   to the property as the first argument:

   ::

      /> /ceph_cluster/minions/ ls
      o- minions .................................................. [Minions: 5]
        o- ses-master.example.com ................................... [no roles]
        o- ses-min1.example.com ..................................... [no roles]
      [...]

..

   **Tip**

   While in a ceph-salt shell, you can use the autocompletion feature
   similar to a normal Linux shell (Bash) autocompletion. It completes
   configuration paths, subcommands, or Salt Minion names. When
   autocompleting a configuration path, you have two options:

   -  To let the shell finish a path relative to your current position,
      hit the TAB key twice.

   -  To let the shell finish an absolute path, enter / and hit the TAB
      key twice.

   **Tip**

   If you enter ``cd`` from the ceph-salt shell without any path, the
   command will print a tree structure of the cluster configuration with
   the line of the current path active. You can use the up and down
   cursor keys to navigate through individual lines. After you confirm
   with , the configuration path will change to the last active one.

..

   **Important**

   To keep the documentation consistent, we will use a single command
   syntax without entering the ceph-salt shell. For example, you can
   list the cluster configuration tree by using the following command:

   ::

      root@master # ceph-salt config ls

.. _deploy-cephadm-configure-minions:

Add Salt Minions
~~~~~~~~~~~~~~~~

Include all or a subset of Salt Minions that we deployed and accepted in
`Deploy Salt <#deploy-salt>`__ to the Ceph cluster configuration. You
can either specify the Salt Minions by their full names, or use a glob
expressions '*' and '?' to include multiple Salt Minions at once. Use
the ``add`` subcommand under the ``/ceph_cluster/minions`` path. The
following command includes all accepted Salt Minions:

::

   root@master # ceph-salt config /ceph_cluster/minions add '*'

Verify that the specified Salt Minions were added:

::

   root@master # ceph-salt config /ceph_cluster/minions ls
   o- minions ................................................. [Minions: 5]
     o- ses-master.example.com .................................. [no roles]
     o- ses-min1.example.com .................................... [no roles]
     o- ses-min2.example.com .................................... [no roles]
     o- ses-min3.example.com .................................... [no roles]
     o- ses-min4.example.com .................................... [no roles]

.. _deploy-cephadm-configure-cephadm:

Specify Salt Minions Managed by cephadm
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Specify which minions will belong to the Ceph cluster and will be
managed by cephadm:

::

   root@master # ceph-salt config /ceph_cluster/roles/cephadm add '*'

.. _deploy-cephadm-configure-admin:

Specify Admin Node
~~~~~~~~~~~~~~~~~~

The Admin Node is the node where the ``ceph.conf`` configuration file
and the Ceph admin keyring is installed. You usually run Ceph related
commands on the Admin Node.

   **Tip**

   In a homogeneous environment where all or most hosts belong to SUSE
   Enterprise Storage, we recommend having the Admin Node on the same
   host as the Salt Master.

   In a heterogeneous environment where one Salt infrastructure hosts
   more than one cluster, for example, SUSE Enterprise Storage together
   with SUSE Manager, do *not* place the Admin Node on the same host as
   Salt Master.

To specify the Admin Node, run the following command:

::

   root@master # ceph-salt config /ceph_cluster/roles/admin add ses-master.example.com
   1 minion added.
   root@master # ceph-salt config /ceph_cluster/roles/admin ls
   o- admin ................................................... [Minions: 1]
     o- ses-master.example.com ...................... [Other roles: cephadm]

..

   **Tip**

   You can install the Ceph configuration file and admin keyring on
   multiple nodes if you deployment requires it. For security reasons,
   avoid installing them on all the cluster's nodes.

.. _deploy-cephadm-configure-mon:

Specify First MON/MGR Node
~~~~~~~~~~~~~~~~~~~~~~~~~~

You need to specify which of the cluster's Salt Minions will bootstrap
the cluster. This minion will become the first one running Ceph Monitor
and Ceph Manager services.

::

   root@master # ceph-salt config /ceph_cluster/roles/bootstrap set ses-min1.example.com
   Value set.
   root@master # ceph-salt config /ceph_cluster/roles/bootstrap ls
   o- bootstrap ..................................... [ses-min1.example.com]

..

   **Important**

   The minion that will bootstrap the cluster needs to have the admin
   keyring as well:

   ::

      root@master # ceph-salt config /ceph_cluster/roles/admin add ses-min1.example.com
      1 minion added.
      root@master # ceph-salt config /ceph_cluster/roles/admin ls
      o- admin ................................................... [Minions: 2]
        o- ses-master.example.com ............................ [no other roles]
        o- ses-min1.example.com ...................... [other roles: bootstrap]

.. _deploy-cephadm-configure-ssh:

Generate SSH Key Pair
~~~~~~~~~~~~~~~~~~~~~

cephadm uses the SSH protocol to communicate with cluster nodes. You
need to generate the private and public part of the SSH key pair:

::

   root@master # ceph-salt config /ssh generate
   Key pair generated.
   root@master # ceph-salt config /ssh ls
   o- ssh ................................................... [Key Pair set]
     o- private_key ...... [53:b1:eb:65:d2:3a:ff:51:6c:e2:1b:ca:84:8e:0e:83]
     o- public_key ....... [53:b1:eb:65:d2:3a:ff:51:6c:e2:1b:ca:84:8e:0e:83]

.. _deploy-cephadm-configure-ntp:

Configure Time Server
~~~~~~~~~~~~~~~~~~~~~

Select one of the Salt Minions to be a time server for the rest of the
cluster, and configure it to synchronize its time with a reliable time
source outside of the cluster.

::

   root@master # ceph-salt config /time_server/server_hostname set ses-master.example.com
   root@master # ceph-salt config /time_server/external_servers add pool.ntp.org

The ``/time_server/subnet`` option specifies the subnet from which NTP
clients are allowed to access the NTP server. It is automatically set
when you specify ``/time_server/server_hostname``. If you need to change
it or specify it manually, run:

::

   root@master # ceph-salt config /time_server/subnet set 10.20.6.0/24

For more details, refer to the ``man 5 chrony.conf`` manual page and
search for the ``allow`` directive.

Check the time server settings:

::

   root@master # ceph-salt config /time_server ls
   o- time_server ................................................ [enabled]
     o- external_servers ............................................... [1]
     | o- pool.ntp.org ............................................... [...]
     o- server_hostname ........................... [ses-master.example.com]
     o- subnet .............................................. [10.20.6.0/24]

Find more information on setting up time synchronization in
https://documentation.suse.com/sles/15-SP2/html/SLES-all/cha-ntp.html#sec-ntp-yast.

.. _deploy-cephadm-configure-dashboardlogin:

Configure Ceph Dashboard Login Credentials
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Ceph Dashboard will be available after the basic cluster is deployed. To
access it, you need to set a valid user name and password, for example:

::

   root@master # ceph-salt config /cephadm_bootstrap/dashboard/username set admin
   root@master # ceph-salt config /cephadm_bootstrap/dashboard/password set PWD

.. _deploy-cephadm-configure-imagepath:

Configure Path to Container Images
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

cephadm needs to know a valid URI path to container images that will be
used during the deployment step. Verify whether the default path is set:

::

   root@master # ceph-salt config /containers/images/ceph ls

If there is no default path set or your deployment requires a specific
path, add it as follows:

::

   root@master # ceph-salt config /containers/images/ceph set registry.suse.com/ses/7/ceph/ceph

.. _deploy-cephadm-configure-registry:

Configure Container Registry
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Optionally, you can set an alternative container registry. This will
serve as a mirror of a public online registry and is useful in the
following scenarios:

-  You have a lot of cluster nodes and want to save download time and
   bandwidth by creating a local mirror of container images.

-  Your cluster has no access to the online registry (an air-gapped
   deployment) and you need a local mirror to pull the container images
   from.

-  You have a good reason to avoid secure access to the registry and
   want to setup and access an insecure one.

..

   **Tip**

   The following procedure uses ``podman`` to create a container
   registry and ``skopeo`` to mirror container images. To install
   podman, you need to add the ``Containers Module`` extension. For more
   information, refer to their manual pages ``man 1 podman`` and
   ``man 1 skopeo``.

To configure a local container registry, follow these steps:

1. Create a local container registry accessible but outside of the Ceph
   cluster, for example:

   ::

      root # podman run -d \
       --restart=always \
       --name registry \
       -p 5000:5000 \
       registry:2

2. Mirror SES 7 related containers to the local registry:

   ::

      root # skopeo copy \
       --dest-tls-verify=false \
       docker://registry.suse.com/ses/7/ceph/ceph \
       docker://LOCAL_REGISTRY_HOST_IP:5000/registry.suse.com/ses/7/ceph/ceph

3. On the Salt Master, add the *insecure* local repository to the
   ceph-salt configuration:

   ::

      root@master # ceph-salt config /containers/registries \
       add prefix=registry.suse.com \
       location=LOCAL_REGISTRY_HOST_IP:5000/registry.suse.com insecure=true

.. _deploy-cephadm-configure-reboots:

Configure Cluster Update and Reboot Behavior
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

You can configure whether software packages will be updated on cluster
nodes during the deployment (see `Deploy
Cluster <#deploy-cephadm-deploy>`__), and whether nodes will
automatically reboot when the update requires it.

By default, package updates and reboots are enabled.

   **Important**

   If the Salt Master is part of the cluster (it is its own minion at
   the same time) and needs to reboot during the deployment, do such
   reboot manually. After the Salt Master reboots, run
   ``ceph-salt apply`` again to continue the deployment.

In rare cases, you may want to disable the automatic update of software
packages on cluster nodes. For example, if you verified that the system
is operating optimally and therefore want to keep the packages at the
current version. To disable software updates, change the
``/system_update/packages`` configuration:

::

   root@master # ceph-salt config /system_update/packages disable

Preventing nodes from automatic reboots is useful if you run cluster
services that should not be interrupted during system updates. To
disable automatic node reboots, change the ``/system_update/reboot``
configuration:

::

   root@master # ceph-salt config /system_update/reboot disable

.. _deploy-cephadm-configure-verify:

Verify Cluster Configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The minimal cluster configuration is finished. Inspect it for obvious
errors:

::

   root@master # ceph-salt config ls
   o- / ............................................................... [...]
     o- ceph_cluster .................................................. [...]
     | o- minions .............................................. [Minions: 5]
     | | o- ses-master.example.com .................................. [admin]
     | | o- ses-min1.example.com ......................... [bootstrap, admin]
     | | o- ses-min2.example.com ................................. [no roles]
     | | o- ses-min3.example.com ................................. [no roles]
     | | o- ses-min4.example.com ................................. [no roles]
     | o- roles ....................................................... [...]
     |   o- admin .............................................. [Minions: 2]
     |   | o- ses-master.example.com ....................... [no other roles]
     |   | o- ses-min1.example.com ................. [other roles: bootstrap]
     |   o- bootstrap ................................ [ses-min1.example.com]
     |   o- cephadm ............................................ [Minions: 5]
     o- cephadm_bootstrap ............................................. [...]
     | o- advanced .................................................... [...]
     | o- ceph_conf ................................................... [...]
     | o- dashboard ................................................... [...]
     |   o- password ................................... [randomly generated]
     |   o- username ................................................ [admin]
     | o- mon_ip ..................................................... [None]
     o- containers .................................................... [...]
     | o- images ...................................................... [...]
     |   o- ceph ........................ [registry.suse.com/ses/7/ceph/ceph]
     | o- registries ................................................ [empty]
     o- ssh .................................................. [Key Pair set]
     | o- private_key ..... [53:b1:eb:65:d2:3a:ff:51:6c:e2:1b:ca:84:8e:0e:83]
     | o- public_key ...... [53:b1:eb:65:d2:3a:ff:51:6c:e2:1b:ca:84:8e:0e:83]
     o- system_update ................................................. [...]
     | o- packages ................................................ [enabled]
     | o- reboot .................................................. [enabled]
     o- time_server ............................................... [enabled]
       o- external_servers .............................................. [1]
       | o- 0.pt.pool.ntp.org ......................................... [...]
       o- server_hostname .......................... [ses-master.example.com]
       o- subnet ............................................. [10.20.6.0/24]

..

   **Tip**

   You can check if the configuration of the cluster is valid by running
   the following command:

   ::

      root@master # ceph-salt status
      hosts:  0/5 managed by cephadm
      config: OK

.. _deploy-cephadm-configure-export:

Export Cluster Configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

After you have configured the basic cluster and its configuration is
valid, it is a good idea to export its configuration to a file:

::

   root@master # ceph-salt export > cluster.json

In case you break the cluster configuration and need to revert to a
backup state, run:

::

   root@master # ceph-salt import cluster.json

.. _deploy-cephadm-deploy:

Deploy Cluster
--------------

Deploy the previously configured minimal Ceph cluster by running the
following command:

::

   root@master # ceph-salt apply

The above command will open an interactive user interface that shows the
current progress of each minion.

.. figure:: cephadm_deploy.png
   :alt: Deployment of Minimal Cluster
   :width: 75.0%

   Deployment of Minimal Cluster

..

   **Tip**

   If you need to apply the configuration from a script, there is also a
   non-interactive mode of deployment. This is also useful when
   deploying the cluster from a remote machine because constant updating
   of the progress information on the screen over the network may become
   distracting:

   ::

      root@master # ceph-salt apply --non-interactive

.. _day2-deployment:

Further Deployment (Day 2)
--------------------------

After you have deployed the basic Ceph cluster, you need to deploy core
services to more cluster nodes. To make the cluster data accessible to
clients, deploy additional services as well.

There are two ways to deploy additional Ceph services:

-  By using the Ceph Dashboard's graphical Web UI. Find more details in
   `Further Deployment (Day 2) Using the Ceph
   Dashboard <#deploy-dashboard-day2>`__.

-  By using the ``ceph orch`` subcommands on the command line. Find more
   details in `Further Deployment (Day 2) Using the Command
   Line <#deploy-cephadm-day2>`__.

.. _deploy-dashboard-day2:

Further Deployment (Day 2) Using the Ceph Dashboard
===================================================

ADDME

.. _deploy-cephadm-day2:

Further Deployment (Day 2) Using the Command Line
=================================================

.. _deploy-cephadm-day2-orch:

The ``ceph orch`` Command
-------------------------

The Ceph orchestrator command ``ceph orch``—which is an interface to the
cephadm module—will take care of listing cluster components and
deploying Ceph services on new cluster nodes.

.. _deploy-cephadm-day2-orch-status:

Displaying the Orchestrator Status
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The following command shows the current mode and status of the Ceph
orchestrator.

::

   cephadm@adm > ceph orch status

.. _deploy-cephadm-day2-orch-list:

Listing Devices, Services, and Daemons
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

To run ``ceph-volume`` on all nodes and list all disk devices, run:

::

   cephadm@adm > ceph orch device ls
   HOST        PATH      TYPE   SIZE  DEVICE  AVAIL  REJECT REASONS
   ses-master  /dev/vda  hdd   16.0G          False  locked
   ses-min1    /dev/vdb  hdd   20.0G          True
   ses-min1    /dev/vda  hdd   16.0G          False  locked
   ses-min2    /dev/vdb  hdd   20.0G          True
   [...]

..

   **Tip**

   *Service* is a general term for a Ceph service of a specific type,
   for example Ceph Manager.

   *Daemon* is a specific instance of a service, for example a process
   ``mgr.ses-min1.gdlcik`` running on a node called ``ses-min1``.

To list all services known to cephadm, run:

::

   cephadm@adm > ceph orch ls
   NAME  RUNNING  REFRESHED  AGE  PLACEMENT  IMAGE NAME                  IMAGE ID
   mgr       1/0  5m ago     -    <no spec>  registry.example.com/[...]  5bf12403d0bd
   mon       1/0  5m ago     -    <no spec>  registry.example.com/[...]  5bf12403d0bd

..

   **Tip**

   You can limit the list to services on a particular node with the
   optional ``–host`` parameter and services of a particular type with
   the optional ``–type`` parameter (accepts ``mon``, ``osd``, ``mgr``,
   ``mds``, and ``rgw``).

To list all running daemons deployed by cephadm, run:

::

   cephadm@adm > ceph orch ps
   NAME            HOST     STATUS   REFRESHED AGE VERSION    IMAGE ID     CONTAINER ID
   mgr.ses-min1.gd ses-min1 running) 8m ago    12d 15.2.0.108 5bf12403d0bd b8104e09814c
   mon.ses-min1    ses-min1 running) 8m ago    12d 15.2.0.108 5bf12403d0bd a719e0087369

..

   **Tip**

   To query the status of a particular daemon, use ``--daemon_type`` and
   ``--daemon_id``. For OSDs, the ID is the numeric OSD ID. For MDS, the
   ID is the file system name:

   ::

      cephadm@adm > ceph orch ps --daemon_type osd --daemon_id 0
      cephadm@adm > ceph orch ps --daemon_type mds --daemon_id my_cephfs

.. _cephadm-service-and-placement-specs:

Service and Placement Specification
-----------------------------------

The recommended way to specify the deployment of Ceph services is to
create a YAML file—for example, ``cluster.yml``—that describes which
nodes will run specific services, for example:

::

   cephadm@adm > cat cluster.yml
   [...]
   service_type: nfs
   service_id: EXAMPLE_NFS
   placement:
     hosts:
       - host1
       - host2
   specs:
    pool: EXAMPLE_POOL
    namespace: EXAMPLE_NAMESPACE
   [...]

The aforementioned properties have the following meaning:

``service_type``
   The type of the service. It can be either a Ceph service (``mon``,
   ``mgr``, ``mds``, ``crash``, ``osd``, or ``rbd-mirror``), a gateway
   (``nfs`` or ``rgw``), or part of the monitoring stack
   (``alertmanager``, ``grafana``, ``node-exporter``, or
   ``prometheus``).

``service_id``
   The name of the service. Specifications of type ``mon``, ``mgr``,
   ``alertmanager``, ``grafana``, ``node-exporter``, and ``prometheus``
   do not require the ``service_id`` property.

``placement``
   Specifies which nodes will be running the service. Refer to
   `Placement Specification <#cephadm-placement-specs>`__ for more
   details.

``spec``
   Additional specification relevant for the service type.

..

   **Tip**

   Ceph cluster services have usually a number of properties specific to
   them. For examples and details of individual services' specification,
   refer to `Deploying Services to
   Nodes <#deploy-cephadm-day2-services>`__.

.. _cephadm-placement-specs:

Placement Specification
~~~~~~~~~~~~~~~~~~~~~~~

To deploy Ceph services, cephadm needs to know on which nodes to deploy
them. Use the ``placement`` property and list the short host names of
the nodes that the service applies to:

::

   cephadm@adm > cat cluster.yml
   [...]
    placement:
     hosts:
      - host1
      - host2
      - host3
   [...]

.. _drive-groups:

OSD Specification
~~~~~~~~~~~~~~~~~

*DriveGroups* specify the layouts of OSDs in the Ceph cluster. They are
defined in a single YAML file. In this section, we will use
``drive_groups.yml`` as an example.

An administrator should manually specify a group of OSDs that are
interrelated (hybrid OSDs that are deployed on a mixture of HDDs and
SDDs) or share identical deployment options (for example, the same
object store, same encryption option, stand-alone OSDs). To avoid
explicitly listing devices, DriveGroups use a list of filter items that
correspond to a few selected fields of ``ceph-volume``'s inventory
reports. cephadm will provide code that translates these DriveGroups
into actual device lists for inspection by the user.

To apply OSD specification to your cluster, run

::

   cephadm@adm > ceph orch apply osd -i drive_groups.yml

.. _drive-groups-specs:

Specification
^^^^^^^^^^^^^

Following is an example DriveGroups specification file:

::

   service_type: osd
   service_id: example_drvgrp_name
   placement:
    host_pattern: '*'
   data_devices:
     drive_spec: DEVICE_SPECIFICATION
   db_devices:
     drive_spec: DEVICE_SPECIFICATION
   wal_devices:
     drive_spec: DEVICE_SPECIFICATION
   block_wal_size: '5G'  # (optional, unit suffixes permitted)
   block_db_size: '5G'   # (optional, unit suffixes permitted)
   osds_per_device: 1   # number of osd daemons per device
   encryption:           # 'True' or 'False' (defaults to 'False')

Matching Disk Devices
^^^^^^^^^^^^^^^^^^^^^

You can describe the specification using the following filters:

-  By a disk model:

   ::

      model: DISK_MODEL_STRING

-  By a disk vendor:

   ::

      vendor: DISK_VENDOR_STRING

   ..

      **Tip**

      Always enter the DISK_VENDOR_STRING in lower case.

-  Whether a disk is rotational or not. SSDs and NVMe drives are not
   rotational.

   ::

      rotational: 0

-  Deploy a node using *all* available drives for OSDs:

   ::

      data_devices:
        all: true

-  Additionally, by limiting the number of matching disks:

   ::

      limit: 10

Filtering Devices by Size
^^^^^^^^^^^^^^^^^^^^^^^^^

You can filter disk devices by their size—either by an exact size, or a
size range. The ``size:`` parameter accepts arguments in the following
form:

-  '10G' - Includes disks of an exact size.

-  '10G:40G' - Includes disks whose size is within the range.

-  ':10G' - Includes disks less than or equal to 10 GB in size.

-  '40G:' - Includes disks equal to or greater than 40 GB in size.

::

   service_type: osd
   service_id: example_drvgrp_name
   placement:
    host_pattern: '*'
   data_devices:
     size: '40TB:'
   db_devices:
     size: ':2TB'

..

   **Note**

   When using the ':' delimiter, you need to enclose the size in quotes,
   otherwise the ':' sign will be interpreted as a new configuration
   hash.

   **Tip**

   Instead of Gigabytes (G), you can specify the sizes in Megabytes (M)
   or Terabytes (T).

.. _ds-drive-groups-examples:

Examples
^^^^^^^^

This section includes examples of different OSD setups.

This example describes two nodes with the same setup:

-  20 HDDs

   -  Vendor: Intel

   -  Model: SSD-123-foo

   -  Size: 4 TB

-  2 SSDs

   -  Vendor: Micron

   -  Model: MC-55-44-ZX

   -  Size: 512 GB

The corresponding ``drive_groups.yml`` file will be as follows:

::

   service_type: osd
   service_id: example_drvgrp_name
   placement:
    host_pattern: '*'
   data_devices:
     model: SSD-123-foo
   db_devices:
     model: MC-55-44-XZ
      

Such a configuration is simple and valid. The problem is that an
administrator may add disks from different vendors in the future, and
these will not be included. You can improve it by reducing the filters
on core properties of the drives:

::

   service_type: osd
   service_id: example_drvgrp_name
   placement:
    host_pattern: '*'
   data_devices:
     rotational: 1
   db_devices:
     rotational: 0
      

In the previous example, we are enforcing all rotating devices to be
declared as 'data devices' and all non-rotating devices will be used as
'shared devices' (wal, db).

If you know that drives with more than 2 TB will always be the slower
data devices, you can filter by size:

::

   service_type: osd
   service_id: example_drvgrp_name
   placement:
    host_pattern: '*'
   data_devices:
     size: '2TB:'
   db_devices:
     size: ':2TB'

This example describes two distinct setups: 20 HDDs should share 2 SSDs,
while 10 SSDs should share 2 NVMes.

-  20 HDDs

   -  Vendor: Intel

   -  Model: SSD-123-foo

   -  Size: 4 TB

-  12 SSDs

   -  Vendor: Micron

   -  Model: MC-55-44-ZX

   -  Size: 512 GB

-  2 NVMes

   -  Vendor: Samsung

   -  Model: NVME-QQQQ-987

   -  Size: 256 GB

Such a setup can be defined with two layouts as follows:

::

   service_type: osd
   service_id: example_drvgrp_name
   placement:
    host_pattern: '*'
   data_devices:
     rotational: 0
   db_devices:
     model: MC-55-44-XZ

::

   service_type: osd
   service_id: example_drvgrp_name2
   placement:
    host_pattern: '*'
   data_devices:
     model: MC-55-44-XZ
   db_devices:
     vendor: samsung
     size: 256GB

The previous examples assumed that all nodes have the same drives.
However, that is not always the case:

Nodes 1-5:

-  20 HDDs

   -  Vendor: Intel

   -  Model: SSD-123-foo

   -  Size: 4 TB

-  2 SSDs

   -  Vendor: Micron

   -  Model: MC-55-44-ZX

   -  Size: 512 GB

Nodes 6-10:

-  5 NVMes

   -  Vendor: Intel

   -  Model: SSD-123-foo

   -  Size: 4 TB

-  20 SSDs

   -  Vendor: Micron

   -  Model: MC-55-44-ZX

   -  Size: 512 GB

You can use the 'target' key in the layout to target specific nodes.
Salt target notation helps to keep things simple:

::

   service_type: osd
   service_id: example_drvgrp_one2five
   placement:
    host_pattern: 'node[1-5]'
   data_devices:
     rotational: 1
   db_devices:
     rotational: 0

followed by

::

   service_type: osd
   service_id: example_drvgrp_rest
   placement:
    host_pattern: 'node[6-10]'
   data_devices:
     model: MC-55-44-XZ
   db_devices:
     model: SSD-123-foo

All previous cases assumed that the WALs and DBs use the same device. It
is however possible to deploy the WAL on a dedicated device as well:

-  20 HDDs

   -  Vendor: Intel

   -  Model: SSD-123-foo

   -  Size: 4 TB

-  2 SSDs

   -  Vendor: Micron

   -  Model: MC-55-44-ZX

   -  Size: 512 GB

-  2 NVMes

   -  Vendor: Samsung

   -  Model: NVME-QQQQ-987

   -  Size: 256 GB

::

   service_type: osd
   service_id: example_drvgrp_name
   placement:
    host_pattern: '*'
   data_devices:
     model: MC-55-44-XZ
   db_devices:
     model: SSD-123-foo
   wal_devices:
     model: NVME-QQQQ-987

In the following setup, we are trying to define:

-  20 HDDs backed by 1 NVMe

-  2 HDDs backed by 1 SSD(db) and 1 NVMe (wal)

-  8 SSDs backed by 1 NVMe

-  2 SSDs stand-alone (encrypted)

-  1 HDD is spare and should not be deployed

The summary of used drives is as follows:

-  23 HDDs

   -  Vendor: Intel

   -  Model: SSD-123-foo

   -  Size: 4 TB

-  10 SSDs

   -  Vendor: Micron

   -  Model: MC-55-44-ZX

   -  Size: 512 GB

-  1 NVMe

   -  Vendor: Samsung

   -  Model: NVME-QQQQ-987

   -  Size: 256 GB

The DriveGroups definition will be the following:

::

   service_type: osd
   service_id: example_drvgrp_hdd_nvme
   placement:
    host_pattern: '*'
   data_devices:
     rotational: 0
   db_devices:
     model: NVME-QQQQ-987
    

::

   service_type: osd
   service_id: example_drvgrp_hdd_ssd_nvme
   placement:
    host_pattern: '*'
   data_devices:
     rotational: 0
   db_devices:
     model: MC-55-44-XZ
   wal_devices:
     model: NVME-QQQQ-987
    

::

   service_type: osd
   service_id: example_drvgrp_ssd_nvme
   placement:
    host_pattern: '*'
   data_devices:
     model: SSD-123-foo
   db_devices:
     model: NVME-QQQQ-987
    

::

   service_type: osd
   service_id: example_drvgrp_standalone_encrypted
   placement:
    host_pattern: '*'
   data_devices:
     model: SSD-123-foo
   encryption: True
    

One HDD will remain as the file is being parsed from top to bottom.

.. _cephadm-appply-cluster-specs:

Applying Cluster Specification
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

After you have created a full ``cluster.yml`` file with specifications
of all services and their placement, you can apply the cluster by
running the following command:

::

   cephadm@adm > ceph orch apply -i cluster.yml

.. _deploy-cephadm-day2-addnode:

Adding a New Node
-----------------

To add a new node to a Ceph cluster, follow these steps:

1. Install SUSE Linux Enterprise Server and SUSE Enterprise Storage on
   the new node. Refer to `Install and Configure SUSE Linux Enterprise
   Server <#deploy-os>`__ for more information.

2. Configure the node as a Salt Minion of an already existing Salt
   Master. Refer to `Deploy Salt <#deploy-salt>`__ for more information.

3. Add the new minion to ceph-salt, for example:

   ::

      root@master # ceph-salt config /ceph_cluster/minions add ses-min5.example.com
      root@master # ceph-salt deploy ses-min5.example.com

   Refer to `Add Salt Minions <#deploy-cephadm-configure-minions>`__ for
   more information.

4. Verify that the node was added:

   ::

      cephadm@adm > ceph-salt config /ceph_cluster/minions ls
      o- minions ................................................. [Minions: 5]
      [...]
        o- ses-min5.example.com .................................... [no roles]

.. _deploy-cephadm-day2-services:

Deploying Services to Nodes
---------------------------

After you have added a node to the ceph-salt environment as described in
`Adding a New Node <#deploy-cephadm-day2-addnode>`__, you can deploy
Ceph service(s) to it.

.. _deploy-cephadm-day2-service-mon:

Deploy Ceph Monitors and Ceph Managers
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Ceph cluster has three or five MONs deployed across different nodes. If
there are five or more nodes in the cluster, we recommend deploying five
MONs. A good practice is to have MGRs deployed on the same nodes as
MONs.

   **Important**

   When deploying MONs and MGRs, remember to include the first MON that
   you added when configuring the basic cluster in `Specify First
   MON/MGR Node <#deploy-cephadm-configure-mon>`__.

To deploy MONs, apply the following specification:

::

   service_type: mon
   placement:
    hosts:
     - ses-min1
     - ses-min2
     - ses-min3

Similarly, to deploy MGRs, apply the following specification:

::

   service_type: mgr
   placement:
    hosts:
     - ses-min1
     - ses-min2
     - ses-min3

..

   **Tip**

   If MONs or MGRs are *not* on the same subnet, you need to append the
   subnet addresses. For example:

   ::

      service_type: mon
      placement:
       hosts:
        - ses-min1:10.1.2.0/24
        - ses-min2:10.1.5.0/24
        - ses-min3:10.1.10.0/24

.. _deploy-cephadm-day2-service-osd:

Deploy Ceph OSDs
~~~~~~~~~~~~~~~~

   **Important**

   A storage device is considered *available* if all of the following
   conditions are met:

   -  The device has no partitions.

   -  The device does not have any LVM state.

   -  The device is not be mounted.

   -  The device does not contain a file system.

   -  The device does not contain a BlueStore OSD.

   -  The device is larger than 5 GB.

   If the above conditions are not met, Ceph refuses to provision such
   OSDs.

There are two ways you can deploy OSDs:

-  Tell Ceph to consume all available and unused storage devices:

   ::

      cephadm@adm > ceph orch apply osd --all-available-devices

-  Use DriveGroups (see `OSD Specification <#drive-groups>`__) to create
   OSD specification describing devices that will be deployed based on
   their properties, such as device type (SSD or HDD), device model
   names, size, or the hosts on which the devices exist. Then apply the
   specification by running the following command:

   ::

      cephadm@adm > ceph orch apply osd -i drive_groups.yml

.. _deploy-cephadm-day2-service-mds:

Deploy Metadata Servers
~~~~~~~~~~~~~~~~~~~~~~~

CephFS requires one or more Metadata Server (MDS) services. These are
automatically deployed when you create the CephFS. To create a CephFS,
apply the following specification:

::

   service_type: mds
   service_id: CEPHFS_NAME
   placement:
    hosts:
     - ses-min1
     - ses-min2
     - ses-min3

.. _deploy-cephadm-day2-service-ogw:

Deploy Object Gateways
~~~~~~~~~~~~~~~~~~~~~~

cephadm deploys an Object Gateway as a collection of daemons that manage
a particular *realm* and *zone* (refer to `??? <#ceph-rgw-fed>`__ for
more details).

1. If a realm has not been created yet, create it:

   ::

      cephadm@adm > radosgw-admin realm create --rgw-realm=REALM_NAME --default

2. Create a new zonegroup:

   ::

      cephadm@adm > radosgw-admin zonegroup create --rgw-zonegroup=ZONEGROUP_NAME  \
       --master --default

3. Create a zone:

   ::

      cephadm@adm > radosgw-admin zone create --rgw-zonegroup=ZONEGROUP_NAME \
       --rgw-zone=ZONE_NAME --master --default

4. Finally, apply the following specification to deploy a set of Object
   Gateway daemons for a particular realm and zone:

   ::

      service_type: rgw
      service_id: REALM.ZONE
      placement:
       hosts:
        - ses-min1
        - ses-min2
        - ses-min3

.. _deploy-cephadm-day2-service-nfs:

Deploy NFS Ganesha
~~~~~~~~~~~~~~~~~~

cephadm deploys NFS Ganesha using a pre-defined RADOS pool and an
optional namespace. To deploy NFS Ganesha, apply the following
specification:

::

   service_type: nfs
   service_id: EXAMPLE_NFS
   placement:
    hosts:
     - ses-min1
     - ses-min2
    spec:
    pool: EXAMPLE_POOL
    namespace: EXAMPLE_NAMESPACE

.. _deploy-cephadm-day2-cephupgrade:

Upgrading Ceph
--------------

You can instruct cephadm to upgrade Ceph from one bugfix release to
another. The automated upgrade of Ceph services respects the recommended
order—it starts with Ceph Managers, Ceph Monitors, and then continues on
other services such as Ceph OSDs, Metadata Servers, and Object Gateways.
Each daemon is restarted only after Ceph indicates that the cluster will
remain available.

.. _deploy-cephadm-day2-cephupgrade-start:

Starting the Upgrade
~~~~~~~~~~~~~~~~~~~~

Before you start the upgrade, verify that all nodes are currently online
and your cluster is healthy:

::

   cephadm@adm > cephadm shell -- ceph -s

To upgrade (or downgrade) to a specific Ceph release:

::

   cephadm@adm > ceph orch upgrade start --ceph-version VERSION

For example:

::

   cephadm@adm > ceph orch upgrade start --ceph-version 15.2.1

.. _deploy-cephadm-day2-cephupgrade-monitor:

Monitoring the Upgrade
~~~~~~~~~~~~~~~~~~~~~~

Run the following command to determine whether an upgrade is in
progress:

::

   cephadm@adm > ceph orch upgrade status

While the upgrade is in progress, you will see a progress bar in the
Ceph status output:

::

   cephadm@adm > ceph -s
   [...]
     progress:
       Upgrade to docker.io/ceph/ceph:v15.2.1 (00h 20m 12s)
         [=======.....................] (time remaining: 01h 43m 31s)

You can also watch the cephadm log:

::

   cephadm@adm > ceph -W cephadm

.. _deploy-cephadm-day2-cephupgrade-stop:

Cancelling an Upgrade
~~~~~~~~~~~~~~~~~~~~~

You can stop the upgrade process at any time:

::

   cephadm@adm > ceph orch upgrade stop
