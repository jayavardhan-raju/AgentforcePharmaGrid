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
  version   = {1.0.0},
  note      = {Salesforce DX project; Apex, Flow, and Prompt Template assets}
}
```

### APA (7th Edition)

> Raju, J. (2026). *AgentforcePharmaGrid: Agentforce Grid–driven inter-store inventory transfers with DEA compliance and audit trail for Salesforce* (Version 1.0.0) [Computer software]. GitHub. https://github.com/jayavardhan-raju/AgentforcePharmaGrid

### IEEE

> J. Raju, "AgentforcePharmaGrid: Agentforce Grid–driven inter-store inventory transfers with DEA compliance and audit trail for Salesforce," ver. 1.0.0, 2026. [Online]. Available: https://github.com/jayavardhan-raju/AgentforcePharmaGrid

### Chicago (Author-Date)

> Raju, Jayavardhan. 2026. *AgentforcePharmaGrid: Agentforce Grid–Driven Inter-Store Inventory Transfers with DEA Compliance and Audit Trail for Salesforce*. Version 1.0.0. https://github.com/jayavardhan-raju/AgentforcePharmaGrid.

### Plain Text

> Raju, Jayavardhan. AgentforcePharmaGrid: Agentforce Grid–Driven Inter-Store Inventory Transfers with DEA Compliance and Audit Trail for Salesforce. Version 1.0.0. May 2026. GitHub repository: https://github.com/jayavardhan-raju/AgentforcePharmaGrid

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

A DOI gives the project a stable, citable handle that survives URL changes and forks. Zenodo issues DOIs for free for any public GitHub repo.

**Once registered**, add the badge to the README and update CITATION.cff:

```markdown
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20106783.svg)](https://doi.org/10.5281/zenodo.20106783)
```

```yaml
# In CITATION.cff
doi: "10.5281/zenodo.20106782"
identifiers:
  - type: doi
    value: "10.5281/zenodo.20106782"
    description: "Concept DOI (resolves to latest version)"
```

And update the BibTeX above with the DOI:

```bibtex
@software{raju2026agentforcepharmagrid,
  author = {Raju, Jayavardhan},
  title  = {AgentforcePharmaGrid: ...},
  year   = {2026},
  doi    = {10.5281/zenodo.20106782},
  url    = {https://doi.org/10.5281/zenodo.20106782},
  version = {1.0.0}
}
```

The **Concept DOI** always resolves to the latest released version — prefer it in long-lived citations. Each tagged release also gets its own version-specific DOI for reproducibility.

See the README's "Registering a DOI via Zenodo" section for one-time setup steps.

---

## Why Cite?

- **Credit** — Open-source maintainers rarely get paid for the work; a citation is the closest thing to compensation in academic and professional publishing.
- **Provenance** — A citation lets your reader find the exact version you used, which matters when behavior changes between releases.
- **Discoverability** — Citation graphs (Google Scholar, OpenAlex, Semantic Scholar) help others find related work via your paper or post.
- **Sustainability** — Funders and employers increasingly look at citation counts and DOIs as evidence that an open-source project is being used in the real world.

If you use this work, a citation costs you nothing and means a lot. Thank you.
