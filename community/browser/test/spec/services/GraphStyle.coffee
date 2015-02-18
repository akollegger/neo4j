###!
Copyright (c) 2002-2015 "Neo Technology,"
Network Engine for Objects in Lund AB [http://neotechnology.com]

This file is part of Neo4j.

Neo4j is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
###

'use strict'

describe 'Service: GraphStyle', () ->

  # load the service's module
  beforeEach module 'neo4jApp.services'

  styledata =
    'node':
      'color': '#aaa'
      'border-width': '2px'
      'caption': 'Node'
    'node.Actor':
      'color': '#fff'
    'relationship':
      'color': '#BDC3C7'

  grass = """
relationship {
  color: none;
  border-color: #e3e3e3;
  border-width: 1.5px;
}

node.User {
  color: #FF6C7C;
  border-color: #EB5D6C;
  caption: '{name}';
}

node {
  diameter: 40px;
  color: #FCC940;
  border-color: #F3BA25;
}
"""

  # instantiate service
  GraphStyle = {}
  beforeEach

  beforeEach inject (_GraphStyle_) ->
    GraphStyle = _GraphStyle_
    GraphStyle.loadRules(styledata)

  describe '#change', ->
    it 'should change node rules', ->
      GraphStyle.change({isNode:yes}, {color: '#bbb'})
      newColor = GraphStyle.forNode().get('color')
      expect(newColor).toBe '#bbb'

    it 'should change relationship rules', ->
      GraphStyle.change({isRelationship:yes}, {color: '#bbb'})
      newColor = GraphStyle.forRelationship().get('color')
      expect(newColor).toBe '#bbb'


  describe '#forNode: ', ->
    it 'should be able to get parameters for nodes without labels', ->
      expect(GraphStyle.forNode().get('color')).toBe('#aaa')
      expect(GraphStyle.forNode().get('border-width')).toBe('2px')

    it 'should inherit rules from base node rule', ->
      expect(GraphStyle.forNode(labels: ['Actor']).get('border-width')).toBe('2px')
      expect(GraphStyle.forNode(labels: ['Movie']).get('border-width')).toBe('2px')

    it 'should apply rules when specified', ->
      expect(GraphStyle.forNode(labels: ['Actor']).get('color')).toBe('#fff')

    it 'should create new rules for labels that have not been seen before', ->
      expect(GraphStyle.forNode(labels: ['Movie']).get('color')).toBe('#A5ABB6')
      expect(GraphStyle.forNode(labels: ['Person']).get('color')).toBe('#68BDF6')
      sheet = GraphStyle.toSheet()
      expect(sheet['node.Movie']['color']).toBe('#A5ABB6')
      expect(sheet['node.Person']['color']).toBe('#68BDF6')

    it 'should allocate colors that are not already used by existing rules', ->
      GraphStyle.change({isNode:yes, labels: ['Person']}, {color: '#A5ABB6'})
      expect(GraphStyle.forNode(labels: ['Movie']).get('color')).toBe('#68BDF6')
      sheet = GraphStyle.toSheet()
      expect(sheet['node.Person']['color']).toBe('#A5ABB6')
      expect(sheet['node.Movie']['color']).toBe('#68BDF6')

    it 'should stick to first default color once all default colors have been exhausted', ->
      for i in [1..GraphStyle.defaultColors().length]
        GraphStyle.forNode(labels: ["Label #{i}"])

      GraphStyle.change({isNode:yes, labels: ['Person']}, {color: '#A5ABB6'})
      GraphStyle.change({isNode:yes, labels: ['Movie']}, {color: '#A5ABB6'})
      GraphStyle.change({isNode:yes, labels: ['Animal']}, {color: '#A5ABB6'})

  describe '#parse:', ->
    it 'should parse rules from grass text', ->
      expect(GraphStyle.parse(grass).node).toEqual(jasmine.any(Object))

  describe '#resetToDefault', ->
    it 'should reset to the default styling', ->
      GraphStyle.change({isNode:yes}, {color: '#bbb'})
      newColor = GraphStyle.forNode().get('color')
      expect(newColor).toBe '#bbb'
      GraphStyle.resetToDefault()
      color = GraphStyle.forNode().get('color')
      expect(color).toBe('#A5ABB6')
