# Citing AgentforcePharmaGrid

If you use AgentforcePharmaGrid in research, architecture writeups, conference talks, blog posts, or as a reference implementation, please cite it. Citations help others find the work, give credit to maintainers, and let prospective contributors gauge real-world adoption.

---

## GitHub Citation Button

This repository ships a [`CITATION.cff`](CITATION.cff) file. GitHub renders a **"Cite this repository"** button in the right sidebar of the repo home page. Clicking it offers ready-to-copy APA and BibTeX formats generated from the CFF metadata.

If the button doesn't appear, confirm `CITATION.cff` is at the repo root on the default branch and is valid YAML — GitHub will surface validation errors inline.

---

## Citation Formats

### BibTeX

```bibtex
@software{raju2026agentforcepharmagrid,
  author    = {Raju, Jayavardhan},
  title     = {AgentforcePharmaGrid: Agentforce Grid--Driven Inter-Store Inventory
               Transfers with DEA Compliance and Audit Trail for Salesforce},
  year      = {2026},
  month     = {5},
  url       = {https://github.com/jayavardhan-raju/AgentforcePharmaGrid},
  doi       = {10.5281/zenodo.20283941},
  version   = {1.0.0},
  note      = {Salesforce DX project; Apex, Flow, and admin-authored GenAiPromptTemplate}
}
```

### APA (7th Edition)

> Raju, J. (2026). *AgentforcePharmaGrid: Agentforce Grid–driven inter-store inventory transfers with DEA compliance and audit trail for Salesforce* (Version 1.0.0) [Computer software]. https://doi.org/10.5281/zenodo.20283941

### IEEE

> J. Raju, "AgentforcePharmaGrid: Agentforce Grid–driven inter-store inventory transfers with DEA compliance and audit trail for Salesforce," ver. 1.0.0, 2026, doi: 10.5281/zenodo.20283941. [Online]. Available: https://github.com/jayavardhan-raju/AgentforcePharmaGrid

### Chicago (Author-Date)

> Raju, Jayavardhan. 2026. *AgentforcePharmaGrid: Agentforce Grid–Driven Inter-Store Inventory Transfers with DEA Compliance and Audit Trail for Salesforce*. Version 1.0.0. Zenodo. https://doi.org/10.5281/zenodo.20283941.

### Plain Text

> Raju, Jayavardhan. AgentforcePharmaGrid: Agentforce Grid–Driven Inter-Store Inventory Transfers with DEA Compliance and Audit Trail for Salesforce. Version 1.0.0. May 2026. Zenodo. https://doi.org/10.5281/zenodo.20283941

---

## Citing Related Publications

If a blog post, talk, or article describes the design or rationale for AgentforcePharmaGrid, add it here so people can cite the writeup alongside the software:

```bibtex
@misc{raju2026agentforcepharmagridblog,
  author = {Raju, Jayavardhan},
  title  = {Building AgentforcePharmaGrid: An Agentforce Grid Pattern for Compliance-Aware Inventory Transfers},
  year   = {2026},
  howpublished = {Blog post, jayraju.com},
  url    = {https://www.jayraju.com/?post=4}
}
```

> Replace the URL above with the actual post URL once published; until then, the citation can be omitted from external references.

---

## DOI

This project is archived on Zenodo with the **Concept DOI** [10.5281/zenodo.20283941](https://doi.org/10.5281/zenodo.20283941) — it always resolves to the latest released version. Each tagged GitHub release also receives its own version-specific DOI for reproducibility.

The DOI is wired into:

- `README.md` (Zenodo badge in the header)
- `CITATION.cff` (`doi:` field — GitHub's "Cite this repository" button pulls from here)
- The BibTeX, APA, IEEE, Chicago, and plain-text citations above

If you fork this project and want a fresh DOI for your fork, enable the repo at https://zenodo.org/account/settings/github/ and create a new release. Zenodo issues DOIs for free for any public GitHub repo.

**Badge markdown** (already in the README):

```markdown
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20283941.svg)](https://doi.org/10.5281/zenodo.20283941)
```

---

## Why Cite?

- **Credit** — Open-source maintainers rarely get paid for the work; a citation is the closest thing to compensation in academic and professional publishing.
- **Provenance** — A citation lets your reader find the exact version you used, which matters when behavior changes between releases.
- **Discoverability** — Citation graphs (Google Scholar, OpenAlex, Semantic Scholar) help others find related work via your paper or post.
- **Sustainability** — Funders and employers increasingly look at citation counts and DOIs as evidence that an open-source project is being used in the real world.

If you use this work, a citation costs you nothing and means a lot. Thank you.
