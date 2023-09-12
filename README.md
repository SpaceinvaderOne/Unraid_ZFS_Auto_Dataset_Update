# Unraid Auto Dataset Watcher & Converter v2


This script is  for  converting directories into ZFS datasets on an Unraid server and runs in the User Scripts plugin.
It's proficient in processing appdata from Docker Containers, vdisks from VMs and various other locations within a single run. For directories storing appdata or VM vdisk data, the script is able to detect active containers or VMs that are using these folders. It will automatically stop these containers or VMs prior to initiating the conversion.
Set to operate on a schedule via Unraid user scripts, this tool then can continue to monitor datasets, making certain that their associated child folders remain as datasets. This is especially valuable when, for instance, installing a new container: its appdata will be converted automatically. Such functionality is invaluable for users keen on snapshotting individual containers, VMs, or various data structures.

## Overview

The script will do the following

-   Evaluate whether a directory qualifies for conversion from a folder to a ZFS dataset.
-   Intelligently stop relevant Docker containers or VMs that are tied to directories earmarked for ZFS dataset conversion.
-   Generate a new ZFS dataset and transfer the content of the folder to this dataset.
-   Restart the Docker containers or VMs once the conversion wraps up.
-   Provide a detailed report on what has been successfully converted.

## Pre-requisites

Before using the script, ensure the following:

-   Unraid server (version 6.12 or higher) with ZFS support.
-   [User Scripts](https://forums.unraid.net/topic/48286-plugin-user-scripts/) plugin is installed.
-   (Optional) [ZFS Master plugin](https://forums.unraid.net/topic/122261-plugin-zfs-master/) plugin is installed for enhanced ZFS functionality.
-   Plugins are installed via Unraid's Community Apps

## Setup

1.  Install the User Scripts plugin on your Unraid server.
2.  Add a new script and paste in the provided script.
3.  Edit the script's variables according to your specific server configuration and needs.

## Variables

- `dry_run`: Set to "yes" if you only want to simulate a run without making any changes. Set to "no" to actually run the conversion.

#### Docker Containers:

If you want the script to process Docker appdata -

- `should_process_containers`: Set to "yes" this tells the script the location is container appdata so it can safely deal with it.
- `source_pool_where_appdata_is`: Specify the source pool containing the appdata.
- `source_dataset_where_appdata_is`: Specify the source dataset for appdata.

#### Virtual Machines:

If you want the script to process VM vdisks -

- `should_process_vms`: Set to "yes" this tells the script the location  contains vdisks  so it can safely deal with it.
- `source_pool_where_vm_domains_are`: Specify the source pool containing the VM domains.
- `source_dataset_where_vm_domains_are`: Specify the source dataset for VM domains.
- `vm_forceshutdown_wait`: Duration (in seconds) to wait before force stopping a VM if it doesn't shut down gracefully.

### Additional User-Defined Datasets:

This is where you can add other datasets (non appdata ot vm ones)  to be processed by the script:

- `source_datasets_array`: Specify custom paths in the format pool/dataset, e.g., "tank/mydata".


## Running the Script

After you have configured the script, follow these steps:

1.  Save any changes you've made to the script.
2.  Run the script using the User Scripts plugin. For the initial run, if there are a significant number of folders requiring conversion, click  the 'Run in Background' button. This ensures that you won't have to keep the browser window open, as closing it would otherwise terminate the script.
3.  Configure the script to operate on a schedule that suits your needs, ensuring automated and timely conversions.

------------------------------------------------------------------
------------------------------------------------------------------

**Simplified Working Principle:**

1.  **Initialization**:
    
    -   The script is initialized with several configuration parameters.
    -   `dry_run`: If set to "yes", the script won't make any real changes but will only output what would happen.
    -   `should_process_containers`: If set to "yes", the script will process and convert Docker containers' appdata.
    -   `should_process_vms`: If set to "yes", the script will process and convert Virtual Machines' disk folders.
2.  **Dataset Path Check**:
    
    -   If the user wants to process Docker containers or VMs, their corresponding dataset paths are added to the `source_datasets_array`.
3.  **Utilities**:
    
    -   `find_real_location()`: Identifies the actual physical location of a given path.
    -   `is_zfs_dataset()`: Checks if a given path is a ZFS dataset.
4.  **Stopping Containers**:
    
    -   For each running Docker container:
        -   If a container has bind mounts:
            -   The script identifies the real location of the bind mounts.
            -   If the bind mounts lie within the designated source appdata, the script checks if they're located within a ZFS dataset.
            -   If the appdata is not a ZFS dataset (i.e., it's a folder), the script stops the container, intending to convert the folder to a ZFS dataset later on.
5.  **Stopping VMs**:
    
    -   For each running VM:
        -   The script identifies the VM's disk.
        -   If the disk's real location lies within the designated source VM domains, the script checks if it's inside a ZFS dataset.
        -   If the VM's disk is not a ZFS dataset (i.e., it's a folder), the script attempts to shut down the VM. If it does not shut down within a specified wait time, the VM is forcefully stopped.
6.  **Creating Datasets**:
    
    -   For each folder in the designated source paths:
        -   If the folder is not already a ZFS dataset:
            -   The script checks if there's enough space to create a new dataset.
            -   The folder is renamed with a "_temp" suffix.
            -   A new ZFS dataset is created.
            -   Contents from the "_temp" folder are copied (rsync'd) into the new ZFS dataset.
            -   If the copying is successful and cleanup is enabled, the "_temp" folder is deleted.
7.  **Restarting Containers & VMs**:
    
    -   If containers were stopped earlier, they're restarted after the dataset conversions.
    -   If VMs were stopped earlier, they're restarted after the dataset conversions.
8.  **Logging**:
    
    -   The script logs all actions taken, from the initial dataset path checks to the stopping and restarting of containers and VMs.

_Key Concepts_:

-   **Bind Mount**: A type of mount where a source directory or file is superimposed onto a destination, making its contents accessible from the destination. Used heavily in Unraid Docker templates.
    
-   **ZFS Dataset**: A ZFS dataset can be thought of as a sort of advanced folder with features like compression, quota, and snapshot capabilities.
    
-   **rsync**: A fast, versatile utility for copying files and directories. It's often used for mirroring and backups. Keeps timestamps and permissions etc
    

**How script  Works**:

1.  The script first checks whether it should process Docker containers or VMs based on the user's settings.
2.  For Docker containers, the script examines their bind mounts. If any bind mount's true location resides inside a regular folder (and not a ZFS dataset) in the designated source path for appdata, that container is stopped.
3.  Similarly, for VMs, the script checks the true location of their disks. VMs with disks residing inside regular folders in the designated source path for VM domains are stopped.
4.  With the necessary containers and VMs stopped, the script converts relevant folders in the source paths into ZFS datasets.
5.  Once the conversion process is done, the script restarts the containers and VMs it had stopped.
6. Prints results

**CONTRIBUTE TO THE PROJECT**

Your insights and expertise can make a difference! If you've identified improvements or have suggestions for the script, I'd truly appreciate your contributions. Help me make this tool even better.

I'm open to feedback, code enhancements, or new ideas.


**DISCLAIMER**

While this script has been thoroughly tested and is believed to be reliable, unforeseen edge cases may arise. By using this software, you acknowledge potential risks and agree to use it at your own discretion. The author assumes no responsibility for any unintended outcomes.

Use wisely and responsibly!!!
