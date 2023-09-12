**Changelog for Unraid_ZFS_Auto_Dataset_Update**



[v2.0] - 2023-09-11
Added

    New function to auto stop only Docker containers whose appdata is not ZFS based before conversion.
    New function to auto stop only VMs whose vdisk folder is not a dataset before conversion.
    Ability to add extra datasets to source_datasets_array. Users can now have the script process as many datasets as they like.

Improved

    Various safety checks:
        Check if sources exist.
        Check if sources are datasets.
        Determine if there's any work to be done before script runs. The script will not execute if there's no work needed.

[v1.2] - 2023-09-09
Added

    New function normalize_name to normalize German umlauts in dataset names.

[v1.1] - 2023-07-16
Improved

    Explicit logging when cleanup is disabled. Enhanced feedback regarding rsync operations and errors.

[v1.0] - Original Release
Added

    Initial release of the script designed for Unraid servers to manage ZFS datasets.
    Features:
        Stop Services: Ability to stop Docker containers and VMs.
        Rename Original Directories: Appends "_temp" suffix to directories to be converted.
        Create New Datasets: Converts directories into ZFS datasets.
        Populate New Datasets: Copies data from temporary directory to new dataset.
        Cleanup: Optional removal of temporary directories.
        Restart Services: Restarts Docker containers and VMs after operations.
