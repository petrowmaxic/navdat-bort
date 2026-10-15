#!/usr/bin/env python3
"""Конвертер интерфейсов libglade (GTK2) в формат GtkBuilder (GTK3).

Делает то же, что gtk-builder-convert из GTK2, плюс правки для GTK3:
  * <widget> -> <object>, <glade-interface> -> <interface>;
  * GtkComboBox со свойством items -> GtkComboBoxText с <items>;
  * свойство adjustment у GtkSpinButton -> отдельный объект GtkAdjustment;
  * response_id у кнопок диалога -> <action-widgets>;
  * packing type=tab / label_item -> <child type="tab"> / <child type="label">;
  * вложенное меню у GtkMenuItem -> <child type="submenu">.

Использование: glade2builder.py input.glade output.ui
"""
import sys
import xml.etree.ElementTree as ET

ADJ_FIELDS = ('value', 'lower', 'upper', 'step_increment',
              'page_increment', 'page_size')


def prop(elem, name):
    for p in elem.findall('property'):
        if p.get('name') == name:
            return p
    return None


class Converter:
    def __init__(self):
        self.extra_objects = []

    def convert_widget(self, w):
        w.tag = 'object'
        cls = w.get('class')
        wid = w.get('id')

        if cls == 'GtkComboBox':
            items = prop(w, 'items')
            if items is not None:
                w.remove(items)
                w.set('class', 'GtkComboBoxText')
                lines = [l for l in (items.text or '').split('\n') if l]
                if lines:
                    el = ET.SubElement(w, 'items')
                    for line in lines:
                        it = ET.SubElement(el, 'item')
                        if items.get('translatable') == 'yes':
                            it.set('translatable', 'yes')
                        it.text = line

        adj = prop(w, 'adjustment')
        if adj is not None and adj.text and len(adj.text.split()) == 6:
            adj_id = 'adjustment_%s' % wid
            obj = ET.Element('object', {'class': 'GtkAdjustment', 'id': adj_id})
            for name, value in zip(ADJ_FIELDS, adj.text.split()):
                ET.SubElement(obj, 'property', {'name': name}).text = value
            self.extra_objects.append(obj)
            adj.text = adj_id

        action_widgets = []
        for child in w.findall('child'):
            inner = child.find('widget')
            packing = child.find('packing')
            if inner is not None:
                rid = prop(inner, 'response_id')
                if rid is not None:
                    inner.remove(rid)
                    action_widgets.append((rid.text, inner.get('id')))
            if packing is not None:
                ptype = prop(packing, 'type')
                if ptype is not None:
                    packing.remove(ptype)
                    child.set('type', {'label_item': 'label'}.get(ptype.text, ptype.text))
                if len(packing) == 0:
                    child.remove(packing)
            if (inner is not None and inner.get('class') == 'GtkMenu'
                    and cls in ('GtkMenuItem', 'GtkImageMenuItem')):
                child.set('type', 'submenu')
            if inner is not None:
                action_widgets += self.convert_widget(inner)

        if cls in ('GtkDialog', 'GtkAboutDialog', 'GtkMessageDialog'):
            if action_widgets:
                el = ET.SubElement(w, 'action-widgets')
                for response, widget_id in action_widgets:
                    ET.SubElement(el, 'action-widget',
                                  {'response': response}).text = widget_id
            return []
        return action_widgets

    def convert(self, tree):
        root = tree.getroot()
        if root.tag != 'glade-interface':
            raise ValueError('not a libglade file')
        root.tag = 'interface'
        toplevels = list(root.findall('widget'))
        for w in toplevels:
            self.convert_widget(w)
        root.insert(0, ET.Element('requires', {'lib': 'gtk+', 'version': '3.24'}))
        for i, obj in enumerate(self.extra_objects):
            root.insert(1 + i, obj)
        return tree


def main(src, dst):
    tree = Converter().convert(ET.parse(src))
    ET.indent(tree, space='  ')
    tree.write(dst, encoding='UTF-8', xml_declaration=True)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
