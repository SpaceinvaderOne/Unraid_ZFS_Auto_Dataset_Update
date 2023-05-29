# Unraid Auto Dataset Watcher & Converter

This script is designed to run on an Unraid server using the User Scripts plugin. It allows you to automatically convert top-level directories into datasets within a specific ZFS dataset on your Zpool. This is particularly useful for managing Docker and VM data for better snapshotting and replication.

## Requirements

- Unraid 6.12 or above
- User Scripts plugin
- ZFSMaster plugin (optional but recommended)

## Setup

1. Install the User Scripts plugin on your Unraid server.
2. Add a new script and paste in the provided script.
3. Edit the script's variables according to your specific server configuration and needs.

## Variables

```
dry_run="no"
source_pool="cyberflux"
source_dataset="appdata"
should_stop_containers="yes"
containers_to_keep_running=("container1" "container2")
should_stop_vms="yes"
vms_to_keep_running=("Home Assistant" "vm2")
cleanup="yes"
```

- `dry_run`: This allows you to test the script without making changes to the system. If set to "yes", the script will print out what it would do without actually executing the commands.
- `source_pool` and `source_dataset`: These are the ZFS pool and dataset where your source data resides.
- `should_stop_containers` and `should_stop_vms`: These decide whether the script should stop all Docker containers and VMs while it is running. If you know certain containers or VMs do not need to be stopped (for example, they are already datasets or stored on a separate drive), you can set these to "no".
- `containers_to_keep_running` and `vms_to_keep_running`: These are arrays where you can list the names of specific Docker containers and VMs that should not be stopped by the script.
- `cleanup`: If set to "yes", the script will remove temporary data that was copied to create the new datasets.

## Usage

Once you have configured the script and saved it in User Scripts, you can run it manually or set up a custom schedule for it to run automatically at set intervals.

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

Remember, you can use the `dry_run` mode to simulate the script operation without making any actual changes. This mode allows you to see what the script would do before letting it operate on your data. This is especially useful for debugging and understanding how the script would interact with your specific configuration.
