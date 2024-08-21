//@dart=2.12

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../core.dart';

abstract class RenderZBox extends RenderBox {
  bool _debugSortedValue = false;
  bool _debugTransformedValue = false;

  double sortValue = 0;

  @override
  @mustCallSuper
  void performLayout() {
    _debugTransformedValue = false;
    _buildMatrix();
    performTransformation();
    _debugTransformedValue = true;
    sort();
  }

  Matrix4? _matrix;
  Matrix4 get matrix {
    assert(_matrix != null, 'Matrix accessed before performing layout');
    return _matrix!;
  }

  _buildMatrix() {
    final anchorParentData = parentData;

    _matrix = Matrix4.identity();
    if (anchorParentData is ZParentData) {
      anchorParentData.transforms.forEach((transform) {
        final matrix4 = Matrix4.translationValues(transform.translate.x,
            transform.translate.y, transform.translate.z);

        matrix4.rotateX(transform.rotate.x);
        matrix4.rotateY(-transform.rotate.y);
        matrix4.rotateZ(transform.rotate.z);

        matrix4.scale(transform.scale.x, transform.scale.y, transform.scale.z);
        matrix..multiply(matrix4);
      });
    }
  }

  @override
  bool get sizedByParent => true;

  void performTransformation();

  void performSort();

  int compareSort(RenderZBox renderBox) {
    return sortValue.compareTo(renderBox.sortValue);
  }

  @mustCallSuper
  void sort() {
    _debugSortedValue = true;
    performSort();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    assert(_debugSortedValue, 'requires sorted value');
    debugTransformed();
    super.paint(context, offset);
  }

  void debugTransformed() {
    assert(_debugTransformedValue, 'requires transformation to be performed');
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return constraints.biggest;
  }

  @override
  void performResize() {
    size = constraints.biggest;
    assert(size.isFinite);
  }
}

enum SortMode {
  // Each child inside the group is sorted by its own center
  // The group acts as a proxy
  inherit,
  // Children are sorted following the order in the list
  stack,
  // Children are encapsulated and painted in the order described
  // The group is painted by
  update,
}

class RenderMultiChildZBox extends RenderZBox
    with
        ContainerRenderObjectMixin<RenderZBox, ZParentData>,
        RenderBoxContainerDefaultsMixin<RenderZBox, ZParentData> {
  RenderMultiChildZBox({
    List<RenderZBox>? children,
    SortMode? sortMode = SortMode.inherit,
    ZVector? sortPoint,
  })  : assert(sortMode != null),
        this.sortMode = sortMode,
        _sortPoint = sortPoint {
    addAll(children);
  }

  @override
  void setupParentData(RenderZBox child) {
    if (parentData is ZParentData) {
      child.parentData = (parentData as ZParentData).clone();
      return;
    }
    if (child.parentData is! ZParentData) {
      child.parentData = ZParentData();
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  void performTransformation() {
    final BoxConstraints constraints = this.constraints;

    RenderZBox? child = firstChild;

    while (child != null) {
      final ZParentData childParentData = child.parentData as ZParentData;
      if (child is RenderMultiChildZBox && child.sortMode == SortMode.inherit) {
        child.layout(constraints, parentUsesSize: true);
      } else {
        child.layout(constraints, parentUsesSize: true);
      }
      child = childParentData.nextSibling;
    }
  }

  ZVector? get sortPoint => _sortPoint;
  ZVector? _sortPoint;
  set sortPoint(ZVector? value) {
    if (value == sortPoint) return;
    _sortPoint = value;
    markNeedsLayout();
  }

  List<RenderZBox>? sortedChildren;

  @override
  void performSort() {
    final children = _getFlatChildren();
    if (sortMode == SortMode.stack || sortMode == SortMode.update) {
      if (sortPoint != null) {
        sortValue = _sortPoint!.applyMatrix4(matrix).z;
      } else {
        sortValue = children.fold<double>(0, (previousValue, element) {
              return (previousValue + element.sortValue);
            }) /
            children.length;
      }
    }
    if (sortMode == SortMode.update) {
      children..sort((a, b) => a.compareSort(b));
    }
    sortedChildren = children;
  }

  SortMode? sortMode;

  List<RenderZBox> _getFlatChildren() {
    List<RenderZBox> children = [];

    RenderZBox? child = firstChild;

    while (child != null) {
      final ZParentData childParentData = child.parentData as ZParentData;

      if (child is RenderMultiChildZBox && child.sortMode == SortMode.inherit) {
        children.addAll(child._getFlatChildren());
      } else {
        children.add(child);
      }
      child = childParentData.nextSibling;
    }
    return children;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    assert(sortMode != null);
    if (sortMode == SortMode.inherit) return;

    for (final child in sortedChildren!) {
      context.paintChild(child, offset);
    }
  }

  bool defaultHitTestChildren(BoxHitTestResult result,
      {required Offset position}) {
    if (sortMode == SortMode.inherit) return false;
    // The x, y parameters have the top left of the node's box as the origin.
    List<RenderZBox> children = sortedChildren!;

    for (final child in children.reversed) {
      final bool isHit = child.hitTest(result, position: position);

      if (isHit) return true;
    }
    return false;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hitTestChildren(result, position: position) || hitTestSelf(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

/// Parent data for use with [ZRenderer].
class ZParentData extends ContainerBoxParentData<RenderZBox> {
  List<ZTransform> transforms;

  ZParentData({
    List<ZTransform>? transforms,
  }) : this.transforms = transforms ?? [];

  ZParentData clone() {
    return ZParentData(
      transforms: List<ZTransform>.from(transforms),
    );
  }
}
