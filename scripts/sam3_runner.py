#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-path", required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--task", choices=["detect", "segment"], default="segment")
    parser.add_argument("--model", default="facebook/sam3")
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--boxes", default=None)
    parser.add_argument("--threshold", type=float, default=0.3)
    parser.add_argument("--show-boxes", action="store_true")
    parser.add_argument("--output-image", required=True)
    parser.add_argument("--output-json", required=True)
    args = parser.parse_args()

    repo_path = Path(args.repo_path)
    sys.path.insert(0, str(repo_path))

    from mlx_vlm.models.sam3.generate import (
        _draw_boxes_only,
        _filter_by_regions,
        _load_predictor,
        _parse_boxes,
        build_annotator,
        draw_frame,
        predict_multi,
    )
    from mlx_vlm.generate import wired_limit

    predictor = _load_predictor(args.model, args.threshold, resolution=1008)
    image = Image.open(args.image).convert("RGB")
    width, height = image.size
    box_array = _parse_boxes(args.boxes)

    with wired_limit(predictor.model):
        result = predict_multi(predictor, image, [args.prompt], boxes=box_array)
    if box_array is not None and len(result.scores) > 0:
        result = _filter_by_regions(result, box_array)

    frame_bgr = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
    if args.task == "detect":
        rendered = _draw_boxes_only(frame_bgr, result.scores, result.boxes, args.prompt, height, width)
    else:
        rendered = draw_frame(
            frame_bgr,
            result.masks,
            result.scores,
            result.boxes,
            args.prompt,
            height,
            width,
            show_boxes=args.show_boxes,
            labels=result.labels,
        )

    output_image = Path(args.output_image)
    output_image.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output_image), rendered)

    detections = []
    for index in range(len(result.scores)):
        x1, y1, x2, y2 = result.boxes[index]
        item = {
            "label": result.labels[index] if result.labels else args.prompt,
            "score": float(result.scores[index]),
            "box": [float(x1), float(y1), float(x2), float(y2)],
        }
        if args.task == "segment" and getattr(result, "masks", None) is not None:
            item["maskArea"] = int(result.masks[index].sum())
        detections.append(item)

    payload = {
        "task": args.task,
        "model": args.model,
        "prompt": args.prompt,
        "imagePath": args.image,
        "outputImagePath": str(output_image),
        "detections": detections,
    }
    output_json = Path(args.output_json)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")

    lines = [f"Detections: {len(detections)}"]
    for item in detections:
        line = f"[{item['score']:.2f}] {item['label']} box={tuple(round(v) for v in item['box'])}"
        if "maskArea" in item:
            line += f" mask={item['maskArea']}px"
        lines.append(line)
    print("\n".join(lines))


if __name__ == "__main__":
    main()
