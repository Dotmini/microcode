//! Git operations module
//!
//! Provides Git repository operations using git2 library

use crate::error::{AppError, Result};
use crate::models::{GitCommit, GitFileStatus, GitStatus};
use git2::{Repository, StatusOptions};
use std::path::Path;

/// Get the status of a Git repository
pub async fn status(repo_path: &str) -> Result<GitStatus> {
    let repo = open_repository(repo_path)?;

    // Get current branch
    let head = repo.head().map_err(|e| AppError::GitError(e.to_string()))?;
    let branch = head.shorthand().unwrap_or("HEAD").to_string();

    // Get file statuses
    let mut opts = StatusOptions::new();
    opts.include_untracked(true);
    opts.recurse_untracked_dirs(true);

    let statuses = repo
        .statuses(Some(&mut opts))
        .map_err(|e| AppError::GitError(e.to_string()))?;

    let mut files = Vec::new();
    for entry in statuses.iter() {
        let path = entry.path().unwrap_or("").to_string();
        let status = match entry.status() {
            s if s.is_wt_new() || s.is_index_new() => "added",
            s if s.is_wt_modified() || s.is_index_modified() => "modified",
            s if s.is_wt_deleted() || s.is_index_deleted() => "deleted",
            s if s.is_wt_renamed() || s.is_index_renamed() => "renamed",
            _ => "untracked",
        };

        files.push(GitFileStatus {
            path,
            status: status.to_string(),
        });
    }

    // Calculate ahead/behind
    let (ahead, behind) = calculate_ahead_behind(&repo)?;

    Ok(GitStatus {
        branch,
        files,
        ahead,
        behind,
    })
}

/// Commit changes to the repository
pub async fn commit(repo_path: &str, message: &str) -> Result<()> {
    let repo = open_repository(repo_path)?;

    // Get the signature
    let signature = repo
        .signature()
        .map_err(|e| AppError::GitError(e.to_string()))?;

    // Get the current tree
    let mut index = repo
        .index()
        .map_err(|e| AppError::GitError(e.to_string()))?;
    index
        .add_all(["*"].iter(), git2::IndexAddOption::DEFAULT, None)
        .map_err(|e| AppError::GitError(e.to_string()))?;
    index
        .write()
        .map_err(|e| AppError::GitError(e.to_string()))?;

    let tree_id = index
        .write_tree()
        .map_err(|e| AppError::GitError(e.to_string()))?;
    let tree = repo
        .find_tree(tree_id)
        .map_err(|e| AppError::GitError(e.to_string()))?;

    // Get parent commit
    let parent_commit = match repo.head() {
        Ok(head) => {
            let oid = head
                .target()
                .ok_or_else(|| AppError::GitError("Invalid HEAD".to_string()))?;
            Some(
                repo.find_commit(oid)
                    .map_err(|e| AppError::GitError(e.to_string()))?,
            )
        }
        Err(_) => None,
    };

    // Create commit
    let parents = if let Some(ref parent) = parent_commit {
        vec![parent]
    } else {
        vec![]
    };

    repo.commit(
        Some("HEAD"),
        &signature,
        &signature,
        message,
        &tree,
        parents.as_slice(),
    )
    .map_err(|e| AppError::GitError(e.to_string()))?;

    Ok(())
}

/// Push changes to remote
pub async fn push(repo_path: &str) -> Result<()> {
    let repo = open_repository(repo_path)?;

    let mut remote = repo
        .find_remote("origin")
        .map_err(|e| AppError::GitError(e.to_string()))?;

    let branch = repo
        .head()
        .map_err(|e| AppError::GitError(e.to_string()))?
        .shorthand()
        .unwrap_or("main")
        .to_string();

    let refspec = format!("refs/heads/{}:refs/heads/{}", branch, branch);

    remote
        .push(&[refspec.as_str()], None)
        .map_err(|e| AppError::GitError(e.to_string()))?;

    Ok(())
}

/// Pull changes from remote
pub async fn pull(repo_path: &str) -> Result<()> {
    let repo = open_repository(repo_path)?;

    let mut remote = repo
        .find_remote("origin")
        .map_err(|e| AppError::GitError(e.to_string()))?;

    remote
        .fetch(&["main"], None, None)
        .map_err(|e| AppError::GitError(e.to_string()))?;

    // Perform merge (simplified - in production you'd want to handle conflicts)
    let fetch_head = repo
        .find_reference("FETCH_HEAD")
        .map_err(|e| AppError::GitError(e.to_string()))?;
    let fetch_commit = repo
        .reference_to_annotated_commit(&fetch_head)
        .map_err(|e| AppError::GitError(e.to_string()))?;

    let analysis = repo
        .merge_analysis(&[&fetch_commit])
        .map_err(|e| AppError::GitError(e.to_string()))?;

    if analysis.0.is_up_to_date() {
        return Ok(());
    } else if analysis.0.is_fast_forward() {
        // Fast-forward merge
        let refname = format!("refs/heads/{}", repo.head()?.shorthand().unwrap_or("main"));
        let mut reference = repo
            .find_reference(&refname)
            .map_err(|e| AppError::GitError(e.to_string()))?;
        reference
            .set_target(fetch_commit.id(), "Fast-forward")
            .map_err(|e| AppError::GitError(e.to_string()))?;
        repo.set_head(&refname)
            .map_err(|e| AppError::GitError(e.to_string()))?;
        repo.checkout_head(Some(git2::build::CheckoutBuilder::default().force()))
            .map_err(|e| AppError::GitError(e.to_string()))?;
    }

    Ok(())
}

/// Get commit log
pub async fn log(repo_path: &str, limit: usize) -> Result<Vec<GitCommit>> {
    let repo = open_repository(repo_path)?;

    let mut revwalk = repo
        .revwalk()
        .map_err(|e| AppError::GitError(e.to_string()))?;
    revwalk
        .push_head()
        .map_err(|e| AppError::GitError(e.to_string()))?;

    let mut commits = Vec::new();
    for (i, oid) in revwalk.enumerate() {
        if i >= limit {
            break;
        }

        let oid = oid.map_err(|e| AppError::GitError(e.to_string()))?;
        let commit = repo
            .find_commit(oid)
            .map_err(|e| AppError::GitError(e.to_string()))?;

        let author = commit.author();
        commits.push(GitCommit {
            hash: oid.to_string(),
            author: author.name().unwrap_or("Unknown").to_string(),
            email: author.email().unwrap_or("").to_string(),
            message: commit.message().unwrap_or("").to_string(),
            timestamp: chrono::DateTime::from_timestamp(commit.time().seconds(), 0)
                .map(|dt| dt.to_rfc3339())
                .unwrap_or_default(),
        });
    }

    Ok(commits)
}

/// Get diff
pub async fn diff(repo_path: &str) -> Result<String> {
    let repo = open_repository(repo_path)?;

    let head = repo.head().map_err(|e| AppError::GitError(e.to_string()))?;
    let tree = head
        .peel_to_tree()
        .map_err(|e| AppError::GitError(e.to_string()))?;

    let diff = repo
        .diff_tree_to_workdir_with_index(Some(&tree), None)
        .map_err(|e| AppError::GitError(e.to_string()))?;

    let mut diff_text = String::new();
    diff.print(git2::DiffFormat::Patch, |_delta, _hunk, line| {
        diff_text.push_str(&format!("{}", String::from_utf8_lossy(line.content())));
        true
    })
    .map_err(|e| AppError::GitError(e.to_string()))?;

    Ok(diff_text)
}

// Helper functions

fn open_repository(path: &str) -> Result<Repository> {
    let path_buf = Path::new(path);
    Repository::open(path_buf)
        .map_err(|e| AppError::GitRepositoryNotFound(format!("{}: {}", path, e)))
}

fn calculate_ahead_behind(repo: &Repository) -> Result<(usize, usize)> {
    let head = match repo.head() {
        Ok(head) => head,
        Err(_) => return Ok((0, 0)),
    };

    let local_oid = match head.target() {
        Some(oid) => oid,
        None => return Ok((0, 0)),
    };

    let branch_name = match head.shorthand() {
        Some(name) => name,
        None => return Ok((0, 0)),
    };

    let upstream_name = format!("refs/remotes/origin/{}", branch_name);
    let upstream = match repo.find_reference(&upstream_name) {
        Ok(reference) => reference,
        Err(_) => return Ok((0, 0)),
    };

    let upstream_oid = match upstream.target() {
        Some(oid) => oid,
        None => return Ok((0, 0)),
    };

    match repo.graph_ahead_behind(local_oid, upstream_oid) {
        Ok((ahead, behind)) => Ok((ahead, behind)),
        Err(_) => Ok((0, 0)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_git_operations() {
        // Note: These tests require a valid Git repository
        // In a real scenario, you'd set up a test repository
    }
}
