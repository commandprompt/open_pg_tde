# Documentation contributing guide

Thank you for deciding to contribute and help us improve the **open_pg_tde documentation**!

We welcome contributions from all users and the community. By contributing, you agree to the project [Code of Conduct](../code-of-conduct.md).

If you want to contribute code, see the [Code contribution guide](../CONTRIBUTING.md).

You can contribute to the documentation in one of the following ways:

1. [Submit a pull request (PR) for documentation on GitHub](#edit-documentation-on-github)
2. [Start a discussion](https://github.com/commandprompt/open_pg_tde/discussions)

The `open_pg_tde` documentation is written in Markdown.

## Edit documentation on GitHub

1. Click the **Edit this file** icon next to the page title. The source `.md` file of the page opens in GitHub editor in your browser. If you haven’t worked with the repository before, GitHub creates a [fork](https://docs.github.com/en/github/getting-started-with-github/fork-a-repo) of it for you.

2. Edit the page. You can check your changes on the **Preview** tab.

3. Commit your changes:

- Describe the changes you have made
- Select the **Create a new branch for this commit** and name your branch
- Click **Propose changes** to create the pull request

4. GitHub creates a branch and a commit for your changes. It loads a new page on which you can open a pull request against `commandprompt/open_pg_tde`. The page shows the base branch (the one you offer your changes for), your commit message, and a diff (a visual representation of your changes against the original page). This allows you to make any last-minute changes. When you are ready, click the **Create pull request** button.

5. Your changes will be reviewed and merged into the documentation.

### Edit documentation locally

To edit the documentation locally:

1. Fork this repository.
2. Clone your fork:

```sh
git clone git@github.com:<your-name>/open_pg_tde.git
cd open_pg_tde
git remote add upstream git@github.com:commandprompt/open_pg_tde.git
```

3. Pull the latest changes from upstream:

```sh
git fetch upstream
git merge upstream/main
```

4. Create a branch for your changes. If the change relates to an issue, include the issue number in the branch name:

```sh
git checkout -b 123-short-description upstream/main
```

5. Make and commit your changes. If the change relates to an issue, reference it in the commit message:

   ```
   git add .
   git commit -m "Short summary of the change"
   git push -u origin 123-short-description
   ```

6. Open a pull request against `commandprompt/open_pg_tde`.

### Building the documentation using MkDocs

To verify how your changes look, generate the static site with the documentation. This process is called *building*.

> **NOTE**
> Learn more about the documentation structure in the [Repository structure](#repository-structure) section.

To verify how your changes look, you can generate a static site locally:

1. Install [Python]
2. Install [MkDocs] and the required extensions:

```sh
cd open_pg_tde/documentation
pip install -r requirements.txt
```

3. Build the site:

```sh
mkdocs build
```

4. Open `site/index.html`

Or, to run the built-in web server:

```sh
mkdocs serve
```

View the site at <http://127.0.0.1:8000>

## Repository structure

The repository includes the following directories and files:

- `mkdocs-base.yml` - the base configuration file. It includes general settings and documentation structure.
- `mkdocs.yml` - configuration file. Contains the settings for building the docs with Material theme.
- `docs`:
  - `*.md` - Source markdown files.
  - `assets` - Images, text snippets and templates
    - `images` - Images, logos and favicons
    - `fragments` - Text snippets used in multiple places in docs. 
    - `templates`:
      - `pdf_cover_page.tpl` - The PDF cover page template
  - `css` - Styles
  - `js` - Javascript files
- `_resource`: The set of Material theme templates with our customizations  
  - `.icons` - Custom icons used in the documentation
  - `overrides`:
    - `partials` - The layout templates for various parts of the documentation such as header, copyright and others.
    - `main.html` - The layout template for hosting the documentation
    - `404.html` - The 404 page template
- `_resourcepdf` - The set of Material theme templates with our customizations for PDF builds
- `site` - This is where the output HTML files are put after the build

[MkDocs]: https://www.mkdocs.org/
[Markdown]: https://daringfireball.net/projects/markdown/
[Git]: https://git-scm.com
[Python]: https://www.python.org/downloads/
[Docker]: https://docs.docker.com/get-docker/