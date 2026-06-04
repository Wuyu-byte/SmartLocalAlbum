#!/usr/bin/env python3
"""Convert a MobileCLIP image encoder to Core ML.

Examples:
  python Scripts/convert_mobileclip_image.py \
    --checkpoint checkpoints/mobileclip2_l14.pt \
    --variant MobileCLIP2-L-14 \
    --output-name mobileclip2_l14_image \
    --image-size 224 \
    --output-dir SmartLocalAlbum/Resources/Models

  python Scripts/convert_mobileclip_image.py \
    --checkpoint checkpoints/mobileclip_s2.pt \
    --variant mobileclip_s2 \
    --output-name mobileclip_s2_image \
    --image-size 256 \
    --output-dir SmartLocalAlbum/Resources/Models
"""

from __future__ import annotations

import argparse
from pathlib import Path

import torch


class ImageEncoderWrapper(torch.nn.Module):
    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.model = model
        self.register_buffer(
            "mean",
            torch.tensor([0.48145466, 0.4578275, 0.40821073]).view(1, 3, 1, 1),
            persistent=False,
        )
        self.register_buffer(
            "std",
            torch.tensor([0.26862954, 0.26130258, 0.27577711]).view(1, 3, 1, 1),
            persistent=False,
        )

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        image = (image - self.mean) / self.std
        features = self.model.encode_image(image)
        return torch.nn.functional.normalize(features.float(), dim=-1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mobileclip-repo", type=Path, help="Optional local Apple ml-mobileclip checkout.")
    parser.add_argument("--checkpoint", required=True, type=Path)
    parser.add_argument("--variant", default="MobileCLIP2-L-14")
    parser.add_argument("--output-name", default="mobileclip2_l14_image")
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--image-size", default=224, type=int)
    args = parser.parse_args()

    import coremltools as ct  # noqa: PLC0415
    import open_clip  # noqa: PLC0415

    model, _, _ = open_clip.create_model_and_transforms(
        args.variant,
        pretrained=str(args.checkpoint),
    )
    model.eval()
    wrapper = ImageEncoderWrapper(model).eval()
    sample_image = torch.rand(1, 3, args.image_size, args.image_size)
    traced = torch.jit.trace(wrapper, sample_image)

    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[
            ct.ImageType(
                name="image",
                shape=sample_image.shape,
                scale=1 / 255.0,
                bias=[0.0, 0.0, 0.0],
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name="embedding")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16,
    )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(args.output_dir / f"{args.output_name}.mlpackage"))


if __name__ == "__main__":
    main()
