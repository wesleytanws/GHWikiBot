# List of regular expressions to match code elements
readarray -t regex_list < script/regex.txt

# Set paths and output configurations
repo_dir=""
remote_path="remotes/origin/"
IFS=$'\n'

# Get repository information
repo_name=$1
current_branch=${2:-$(git -C "${repo_dir}repo" branch --show-current)}
repo_last_updated=$(git -C "${repo_dir}repo" log -1 --pretty=format:%cr "${remote_path}$current_branch")

# Print out repository information
printf "%s\n" \
    "" \
    "Repository name: $repo_name" \
    "Current branch: $current_branch" \
    "Last updated: $repo_last_updated" | tee -a /dev/stderr

# Print out the header
printf "%s\n" \
    "" \
    "────────────────────────────────────────────────────────────────────────────────" >> /dev/stderr

# Exclude directories, sidebar and footer
for page in $(ls -p "${repo_dir}wiki" | grep -v -e / -e ^_Sidebar -e ^_Footer); do
    (
        # Make a copy of the repository for parallelism
        cp -rf "${repo_dir}repo" "${repo_dir}snapshot_$page"

        # Get when the page was last updated
        page_timestamp=$(git -C "${repo_dir}wiki" log -1 --pretty=format:%ct -- $page)
        page_last_updated=$(git -C "${repo_dir}wiki" log -1 --pretty=format:%cr -- $page)

        # Get the commit SHA and checkout the snapshot
        snapshot_SHA=${3:-$(git -C "${repo_dir}snapshot_$page" rev-list -1 --before=$page_timestamp "${remote_path}$current_branch")}
        if ((${#snapshot_SHA} != 0)); then
            git -C "${repo_dir}snapshot_$page" checkout -q -f $snapshot_SHA
        fi

        # List of code elements that match any regular expressions
        code_elements=""
        for regex in ${regex_list[@]}; do
            code_elements+=$(grep -ohPI -e $regex "${repo_dir}wiki/$page")
        done

        # Unique code elements less than 80 characters long
        qualified_code_elements=$(printf "%s\n" $code_elements | sort | uniq | awk 'length($0) < 80')

        # Store the references for each category
        missing_ref=$'\n'
        reduced_ref=$'\n'
        perfect_ref=$'\n'
        unknown_ref=$'\n'
        total_refs=0

        if ((${#qualified_code_elements} != 0)); then

            total_refs=$(printf "%s\n" "$qualified_code_elements" | wc -l)

            while read -r code_element; do

                # Count the number of references found in snapshot and repository
                snapshot=0
                if ((${#snapshot_SHA} != 0)); then
                    snapshot=$(grep -rohIF -e $code_element "${repo_dir}snapshot_$page" | wc -l)
                fi
                repo=$(grep -rohIF -e $code_element "${repo_dir}repo" | wc -l)

                # Store the code element in the respective category
                if ((snapshot == repo && repo == 0)); then
                    unknown_ref+="  - $code_element"$'\n'
                elif ((snapshot > repo && repo == 0)); then
                    missing_ref+="  - $code_element ($snapshot ➔ $repo)"$'\n'
                elif ((snapshot > repo && repo > 0)); then
                    reduced_ref+="  - $code_element ($snapshot ➔ $repo)"$'\n'
                else
                    perfect_ref+="  - $code_element ($snapshot ➔ $repo)"$'\n'
                fi
            done < <(printf "%s\n" "$qualified_code_elements")
        fi

        # Count the number of references in each category
        missing_ref_count=$(printf "%s\n" "$missing_ref" | awk 'NF' | wc -l)
        reduced_ref_count=$(printf "%s\n" "$reduced_ref" | awk 'NF' | wc -l)
        perfect_ref_count=$(printf "%s\n" "$perfect_ref" | awk 'NF' | wc -l)
        unknown_ref_count=$(printf "%s\n" "$unknown_ref" | awk 'NF' | wc -l)

        if ((${#snapshot_SHA} == 0)); then
            snapshot_SHA="Not found"
        fi

        # Print out the page summary
        if ((missing_ref_count != 0)); then
            printf "%s\n" \
                "" \
                "$page: $missing_ref_count$(printf "%s\n" "$missing_ref")"
        fi

        # Print out the detailed version
        printf "%s\n" \
            "" \
            "Page name: $page" \
            "Last updated: $page_last_updated" \
            "Snapshot SHA: $snapshot_SHA" \
            "Total references: $total_refs" \
            "" \
            "Missing references: $missing_ref_count$(printf "%s\n" "$missing_ref")" \
            "Reduced references: $reduced_ref_count$(printf "%s\n" "$reduced_ref")" \
            "Perfect references: $perfect_ref_count$(printf "%s\n" "$perfect_ref")" \
            "Unknown references: $unknown_ref_count$(printf "%s\n" "$unknown_ref")" \
            "" \
            "────────────────────────────────────────────────────────────────────────────────" >> /dev/stderr

        # Clean up the snapshot copy
        rm -rf "${repo_dir}snapshot_$page"

        # Store the number of missing references
        printf "$missing_ref_count\n" >> "${repo_dir}missing_ref_count.txt"
    ) &
done
wait

# Count the total number of missing references
total_missing_ref_count=$(paste -sd+ "${repo_dir}missing_ref_count.txt" | bc)
printf "$total_missing_ref_count" >> "total_missing_ref_count.txt"

# Print out the footer
if ((total_missing_ref_count == 0)); then
    printf "%s\n" \
        "" \
        "Missing references: None ✔"
fi

# Clean up the missing reference records
rm -f "${repo_dir}missing_ref_count.txt"

# Helpful links for further actions
printf "%s\n" \
    "" \
    "More details: https://github.com/$repo_name/actions" \
    "Wiki home page: https://github.com/$repo_name/wiki" \
    "" | tee -a /dev/stderr
