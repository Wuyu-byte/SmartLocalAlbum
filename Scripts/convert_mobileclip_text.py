#!/usr/bin/env python3
"""Convert MobileCLIP S2 text encoder to Core ML.

Example:
  python Scripts/convert_mobileclip_text.py \
    --mobileclip-repo ../ml-mobileclip \
    --checkpoint checkpoints/mobileclip_s2.pt \
    --output-dir SmartLocalAlbum/Resources/Models
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch


class TextEncoderWrapper(torch.nn.Module):
    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.model = model

    def forward(self, input_ids: torch.Tensor) -> torch.Tensor:
        features = self.model.encode_text(input_ids)
        return torch.nn.functional.normalize(features.float(), dim=-1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mobileclip-repo", required=True, type=Path)
    parser.add_argument("--checkpoint", required=True, type=Path)
    parser.add_argument("--variant", default="mobileclip_s2")
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--max-length", default=77, type=int)
    args = parser.parse_args()

    sys.path.insert(0, str(args.mobileclip_repo.resolve()))
    import coremltools as ct  # noqa: PLC0415
    import mobileclip  # noqa: PLC0415

    model, _, _ = mobileclip.create_model_and_transforms(
        args.variant,
        pretrained=str(args.checkpoint),
    )
    model.eval()

    tokenizer = mobileclip.get_tokenizer(args.variant)
    sample_text = tokenizer(["猫，猫咪，可爱的猫，家里的猫"])
    if sample_text.ndim == 1:
        sample_text = sample_text.unsqueeze(0)

    wrapper = TextEncoderWrapper(model).eval()
    traced = torch.jit.trace(wrapper, sample_text.to(dtype=torch.int32))

    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[
            ct.TensorType(
                name="input_ids",
                shape=sample_text.shape,
                dtype=np.int32,
            )
        ],
        outputs=[ct.TensorType(name="embedding")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16,
    )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(args.output_dir / "mobileclip_s2_text.mlpackage"))

    encoder = getattr(tokenizer, "encoder", None)
    if encoder:
        tokenizer_path = args.output_dir / "mobileclip_s2_tokenizer.json"
        tokenizer_path.write_text(
            json.dumps(encoder, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
