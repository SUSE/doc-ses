<?xml version="1.0" encoding="UTF-8"?>
<!--
   Purpose:
      Fix conversion issues from Pandoc

   Input:
     DocBook document after conversion with pandoc

   Output:
     Correct DocBook5 document

   Author:    Thomas Schraitle <toms@opensuse.org>
   Copyright (C) 2020 SUSE Software Solutions Germany GmbH

-->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
   xmlns="http://docbook.org/ns/docbook" xmlns:d="http://docbook.org/ns/docbook"
   xmlns:xi="http://www.w3.org/2001/XInclude"
   xmlns:xlink="http://www.w3.org/1999/xlink"
   xmlns:exsl="http://exslt.org/common"
   exclude-result-prefixes="d exsl">

  <xsl:output indent="yes"/>

  <xsl:param name="idprefix">man_</xsl:param>
  <xsl:param name="id"/>

   <xsl:template name="add.root.namespaces">
    <!-- add namespaces to the top output element -->
    <xsl:variable name="temp">
      <xi:foo/>
      <xlink:foo/>
    </xsl:variable>

    <xsl:variable name="nodes" select="exsl:node-set($temp)"/>
    <xsl:for-each select="$nodes//*/namespace::*">
      <xsl:copy-of select="."/>
    </xsl:for-each>
  </xsl:template>

   <xsl:template match="node() | @*" name="copy">
      <xsl:copy>
         <xsl:apply-templates select="@* | node()"/>
      </xsl:copy>
   </xsl:template>

   <xsl:template match="/section">
     <sect1 xml:lang="en">
      <xsl:call-template name="add.root.namespaces"/>
      <xsl:apply-templates select="@* | node()"/>
     </sect1>
   </xsl:template>

   <xsl:template match="*">
      <xsl:element name="{local-name()}"
         namespace="http://docbook.org/ns/docbook">
         <xsl:apply-templates select="node() | @*"/>
      </xsl:element>
   </xsl:template>

  <xsl:template match="literallayout">
    <screen>
      <xsl:apply-templates select="@* | node()"/>
    </screen>
  </xsl:template>

  <xsl:template match="blockquote[variablelist]">
    <xsl:apply-templates select="node()"/>
  </xsl:template>

  <xsl:template match="blockquote[para]">
    <screen>
      <xsl:value-of select="normalize-space(para/text())"/>
    </screen>
  </xsl:template>

  <xsl:template match="section">
    <xsl:variable name="level" select="count(ancestor-or-self::section)"/>

    <xsl:element name="sect{$level}" namespace="http://docbook.org/ns/docbook">
      <xsl:apply-templates select="node() | @*"/>
    </xsl:element>
  </xsl:template>

  <xsl:template name="idfix">
    <xsl:param name="i" select="."/>
    <xsl:variable name="tmp" select="translate(concat($idprefix, $id, $i),
                                     ':-+',
                                     '___')"/>
    <xsl:value-of select="$tmp"/>
  </xsl:template>

  <xsl:template match="@xml:id">
    <xsl:variable name="idfix">
      <xsl:call-template name="idfix">
        <xsl:with-param name="i" select="."/>
      </xsl:call-template>
    </xsl:variable>
    <xsl:attribute name="xml:id">
      <xsl:value-of select="$idfix"/>
    </xsl:attribute>
  </xsl:template>

  <xsl:template match="@linkend">
    <xsl:variable name="idfix">
      <xsl:call-template name="idfix">
        <xsl:with-param name="i" select="."/>
      </xsl:call-template>
    </xsl:variable>
    <xsl:attribute name="linkend">
      <xsl:value-of select="$idfix"/>
    </xsl:attribute>
  </xsl:template>
</xsl:stylesheet>
