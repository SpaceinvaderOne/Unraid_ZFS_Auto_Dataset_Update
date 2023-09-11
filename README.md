# Unraid Auto Dataset Watcher & Converter

```BETA version of script is now also available that will allow multi datasets and auto stop non converted docker containers and vms  -- Unraid_ZFS_Auto_Dataset_Update_Advance.sh```


This script, designed to run on an Unraid server using the User Scripts plugin, is a useful tool for managing your ZFS datasets. It actively monitors specified datasets, checking to ensure all top-level folders are actually ZFS datasets themselves. If any regular directories are detected, the script  converts them into datasets.

This functionality proves especially beneficial when managing, for eaxample, an appdata share set up as a dataset. For instance, when a new Docker container is installed on Unraid, it generates that new container's appdata as a folder within the appdata dataset. This script identifies such instances and converts these folders into individual datasets. Ensuring each Docker container's appdata is isolated in its own dataset allows for precise snapshotting, greatly facilitating rollback operations in case of any issues with a particular container. It provides similar benefits for VMs, transforming newly created VM vdisks - which are typically established as folders - into datasets. These capabilities contribute towards more effective management and recovery of your Docker and VM data.

## Pre-requisites
Before using the script, ensure the following:

- Unraid server (version 6.12 or higher) with ZFS support.
- [User Scripts](https://forums.unraid.net/topic/48286-plugin-user-scripts/) plugin is installed.
- (Optional) [ZFS Master plugin](https://forums.unraid.net/topic/122261-plugin-zfs-master/) plugin is installed for enhanced ZFS functionality.
- Plugins are installed via Unraid's Community Apps

## Setup

1. Install the User Scripts plugin on your Unraid server.
2. Add a new script and paste in the provided script.
3. Edit the script's variables according to your specific server configuration and needs.

## Variables
The variables are located at the top of the script. The script as is contains demo variables which you should change to suit your needs.

```
dry_run="no"
source_pool="cyberflux"
source_dataset="appdata"
should_stop_containers="yes"
containers_to_keep_running=("Emby" "container2")
should_stop_vms="yes"
vms_to_keep_running=("Home Assistant" "vm2")
cleanup="yes"
replace_spaces="no" 
```

- `dry_run`: This allows you to test the script without making changes to the system. If set to "yes", the script will print out what it would do without actually executing the commands.
- `source_pool` and `source_dataset`: These are the ZFS pool name and dataset name where your source data resides which you want the script look for 'regular' directories to convert.
- `should_stop_containers` and `should_stop_vms`: These decide whether the script should stop all Docker containers and VMs while it is running. 
- `containers_to_keep_running` and `vms_to_keep_running`: These are arrays where you can list the names of specific Docker containers and VMs that should not be stopped by the script.
   If you know certain containers or VMs do not need to be stopped (for example, these containers have appdata that is already a dataset or the container ie Plex its appdata is not in a different location.
- `cleanup`: If set to "yes", the script will remove temporary data that was copied to create the new datasets.
- `replace_spaces`: If set to "yes", the script will replace spaces in the names of datasets with underscores. Useful in some situations.

## Usage

Install the script using the Unraid Userscripts Plugin. You can set it to run on a schedule according to your needs.

When running this script manually, it is recommended to run it in the background then view logs to see the progress. This is especially important when running the script for the first time or when there is a large amount of data, as it may take some time. If you run the script in the foreground, the browser page needs to be kept open, otherwise, the script will terminate prematurely.

## Safeguards

This script has been designed with several safeguards to prevent data loss and disruption:

- The script will not stop Docker containers or VMs that are listed in the `containers_to_keep_running` or `vms_to_keep_running` arrays. This prevents unnecessary disruption to these services.
- The script will not create a new dataset if there is not enough space in the ZFS pool. This prevents overfilling the pool and causing issues with existing data.
- The `dry_run` option allows you to see what the script would do without it making any changes. This is useful for testing and debugging the script.

## Simplified Working Principle

Here's how this script operates:

1. **Stopping Services**: If configured to do so, the script will first stop Docker containers and VMs running on your Unraid server. This prevents any data being written to or read from the directories that will be converted, ensuring data consistency and preventing potential corruption. However, you have the option to exclude certain containers or VMs if they do not require stopping, such as if they are already on separate datasets.

2. **Renaming Original Directories**: For each directory identified to be converted into a ZFS dataset, the script first renames it by appending a "_temp" suffix. This is done to prevent name conflicts when creating the new dataset and to safeguard the original data.

3. **Creating New Datasets**: The script then attempts to create a new ZFS dataset with the same name as the original directory. If the new dataset is successfully created, it moves on to the next step. If not (due to an error or insufficient space), the script will skip this directory and proceed to the next one.

4. **Populating New Datasets**: Once the new dataset is created, the script copies the data from the renamed (temporary) directory into the new dataset. This step is crucial as it ensures that all the original data is preserved in the new dataset.

5. **Cleanup**: If the `cleanup` variable is set to "yes", the script will delete the renamed directory and its contents after the data has been successfully copied to the new dataset. This process frees up space in the parent dataset. However, if the dataset creation or data copying fails for any reason, the renamed directory will not be removed, providing an opportunity for you to investigate the issue.

6. **Restarting Services**: Finally, if the script stopped any Docker containers or VMs at the start, it will restart these services. This ensures your applications continue running with minimal downtime.

Remember, you can use the `dry_run` mode to simulate the script operation without making any actual changes. This mode allows you to see what the script would do before letting it operate on your data. This is especially useful for understanding how the script would interact with your specific configuration.
