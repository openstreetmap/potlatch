
	// =====================================================================================
	// Potlatch co-ordinate handling

	// updateCoords - update all co-ordinate global variables

	function updateCoords(tx,ty) {
		_root.bscale=Math.pow(2,_root.scale-_root.flashscale);
		_root.xradius=Stage.width/2;
		_root.yradius=(Stage.height-panelheight)/2;

		_root.map._x=tx; _root.map._y=ty;
		_root.map._xscale=100*bscale;
		_root.map._yscale=100*bscale;

		_root.edge_t=coord2lat ((-_root.map._y          )/bscale); _root.tile_t=lat2tile (edge_t);
		_root.edge_b=coord2lat ((-_root.map._y+2*yradius)/bscale); _root.tile_b=lat2tile (edge_b);
		_root.edge_l=coord2long((-_root.map._x          )/bscale); _root.tile_l=long2tile(edge_l);
		_root.edge_r=coord2long((-_root.map._x+2*xradius)/bscale); _root.tile_r=long2tile(edge_r);

		_root.tile_t=lat2tile (coord2lat ((-_root.bgyoffset-_root.map._y          )/bscale));
		_root.tile_b=lat2tile (coord2lat ((-_root.bgyoffset-_root.map._y+2*yradius)/bscale));
		_root.tile_l=long2tile(coord2long((-_root.bgxoffset-_root.map._x          )/bscale));
		_root.tile_r=long2tile(coord2long((-_root.bgxoffset-_root.map._x+2*xradius)/bscale));
		
		if (_root.panel.scale._visible) { setTypeText('',''); }
	}

	// lat/long <-> coord conversion

	function lat2coord(a)	{ return -(lat2y(a)-basey)*masterscale; }
	function coord2lat(a)	{ return y2lat(a/-masterscale+basey); }
	function long2coord(a)	{ return (a-baselong)*masterscale; }
	function coord2long(a)	{ return a/masterscale+baselong; }
	function y2coord(a)		{ return (a-basey)*-masterscale; }
	function coord2y(a)		{ return a/-masterscale+basey; }
	function y2lat(a) { return 180/Math.PI * (2 * Math.atan(Math.exp(a*Math.PI/180)) - Math.PI/2); }
	function lat2y(a) { return 180/Math.PI * Math.log(Math.tan(Math.PI/4+a*(Math.PI/180)/2)); }
	function centrelat(o)  { return  coord2lat((yradius-_root.map._y-o)/Math.pow(2,_root.scale-_root.flashscale)); }
	function centrelong(o) { return coord2long((xradius-_root.map._x-o)/Math.pow(2,_root.scale-_root.flashscale)); }


	// resizeWindow - user has enlarged/shrunk window

	function resizeWindow() {
		setSizes();
		updateCoords(_root.map._x,_root.map._y);
		_root.lastresize=new Date();
	}

	function setSizes() {
		// resize Yahoo
		clearInterval(_root.yahooresizer);
		if (_root.yahooinited) {
			setYahooSize();
			_root.ylat=centrelat(_root.bgyoffset);
			_root.ylon=centrelong(_root.bgxoffset);
			repositionYahoo(true);
		}
		// resize main mask and panel
		_root.masksquare._height=
		_root.panel._y=Stage.height-panelheight;
		_root.masksquare._width=Stage.width;
		// resize panel window
		if (_root.panel.properties.proptype!='') {
			_root.panel.properties.init(_root.panel.properties.proptype,getPanelColumns(),4);
		} else {
			drawIconPanel();
		}
		_root.panel.i_repeatattr._x=
		_root.panel.i_newattr._x=
		_root.panel.i_newrel._x=120+getPanelColumns()*190;
		// resize other stuff
		_root.waysloading._x=
		_root.tooltip._x=Stage.width-220;
		setStatusPosition();
		for (var w in _root.windows) {
			if (typeof(_root.windows[w])=='movieclip') { _root.windows[w].drawAreas(); }
		}
	}

	function setYahooSize() {
		if (_root.yahoowidth!=Stage.width || _root.yahooheight!=Stage.height-panelheight) {
			_root.yahoowidth=Stage.width;
			_root.yahooheight=Stage.height-panelheight;
			_root.yahoo.myMap.setSize(yahoowidth,yahooheight);
		}
		_root.yahoorightsize=true;
	}

	// updateLinks - update view/edit tabs

	function updateLinks() {
		if (winie) {
			if (gpx) { flash.external.ExternalInterface.call("updatelinks",centrelong(0),centrelat(0),_root.scale,'',_root.edge_l,_root.edge_b,_root.edge_r,_root.edge_t,'gpx',gpx); }
				else { flash.external.ExternalInterface.call("updatelinks",centrelong(0),centrelat(0),_root.scale,'',_root.edge_l,_root.edge_b,_root.edge_r,_root.edge_t); }
		} else {
			var url="javascript:updatelinks("+centrelong(0)+","+centrelat(0)+","+_root.scale+",'',"+_root.edge_l+","+_root.edge_b+","+_root.edge_r+","+_root.edge_t;
			if (gpx) { url+=",'gpx',"+gpx; }
			url=url+")"; getURL(url);
		}
	}
	
	// maximiseSWF - call JavaScript to maximise/minimise
	
	function maximiseSWF() {
		if (_root.maximised) { getURL("javascript:minimiseMap()"); _root.panel.advanced.renameOption(6,iText("advanced_maximise")); }
						else { getURL("javascript:maximiseMap()"); _root.panel.advanced.renameOption(6,iText("advanced_minimise")); }
		_root.maximised=!_root.maximised;
	}

	// =====================================================================================
	// Zoom

	// zoomIn, zoomOut, changeScaleTo - change scale functions
	
	function zoomIn() {
		if (_root.scale<_root.maxscale) {
			if (_root.waycount>500) { purgeWays(); }
			if (_root.poicount>500) { purgePOIs(); }
			zoomTo(_root.scale+1,_root.map._x*2-xradius,_root.map._y*2-yradius,false);
		}
	}
	
	function zoomOut() {
		if (_root.scale>_root.minscale) {
			zoomTo(_root.scale-1,(_root.map._x+xradius)/2,(_root.map._y+yradius)/2,true);
		}
	}

	function zoomTo(newscale,newx,newy,ww,wwforce) {
		var oldwidth=linewidth;
		blankTileQueue();
		changeScaleTo(newscale);
		updateCoords(newx,newy);
		updateLinks();
		redrawBackground();
		resizePOIs();
		if (ww) { whichWays(wwforce); }
		else if (_root.waycount>500) { purgeWays(); }
		redrawWays(oldwidth==linewidth);
		redrawRelations();
	}

	function changeScaleTo(newscale) {
		_root.map.tiles[_root.scale]._visible=false; _root.scale=newscale;
		_root.map.tiles[_root.scale]._visible=true;
		if (_root.scale==_root.minscale) { _root.i_zoomout._alpha=25;  }
									else { _root.i_zoomout._alpha=100; }
		if (_root.scale==_root.maxscale) { _root.i_zoomin._alpha =25;  }
									else { _root.i_zoomin._alpha =100; }
		_root.tolerance=4/Math.pow(2,_root.scale-_root.flashscale);
		_root.poiscale=Math.max(100/Math.pow(2,_root.scale-_root.flashscale),3);
		_root.iconscale=100/Math.pow(2,_root.scale-_root.flashscale);

		_root.anchorsize=_root.iconscale*3;
		if (_root.scale>=16 && _root.scale<=17) { _root.anchorsize *=0.8; }
		if (                   _root.scale<=15) { _root.anchorsize *=0.6; }

		if (preferences.data.thinlines) {
			_root.linewidth=3;
			_root.taggedscale=100/Math.pow(2,_root.scale-_root.flashscale); 
			if (_root.scale>=16) { _root.anchorsize*=0.8; }
		} else {
			_root.linewidth=Math.min(10, 3+Math.pow(Math.max(0,_root.scale-15),2));
			_root.taggedscale=Math.max(100/Math.pow(2,_root.scale-_root.flashscale),5);
			if (_root.scale>=16) { _root.taggedscale*=1.3; }
			if (_root.scale>=17 && _root.scale<=18) { _root.poiscale   *=1.3; }
		}
		if (preferences.data.thinareas) { _root.areawidth=_root.linewidth/3; }
								   else { _root.areawidth=_root.linewidth; }
	}

	function redrawWays(skip) {
		if (_root.wayselected) {
			_root.ws.redraw();
			_root.ws.highlight();
			_root.ws.highlightPoints(5000,"anchor");
		}
		restartElastic();
		_root.redrawlist=new Array();
		if (_root.redrawskip) { _root.redrawskip=skip; }
		for (var qway in _root.map.ways) { _root.redrawlist.push(_root.map.ways[qway]); }
	}

	function redrawRelations() {
		for (var qrel in _root.map.relations) { _root.redrawlist.push(_root.map.relations[qrel]); }
	}

	// =====================================================================================
	// Backgrounds

	function initBackground() {
		preferences.flush();
		setStatusPosition();
		redrawBackground(); 
	}
	
	function resetBackgroundOffset() {
		_root.bgxoffset=0; _root.bgyoffset=0;
	}

	function redrawBackground() {
		var alpha=100-50*preferences.data.dimbackground;
		switch (preferences.data.bgtype) {
			case 4: // No background
					_root.yahoo._visible=false;
					_root.map.tiles._visible=false;
					break;
					
			case 2: // Yahoo
					_root.yahoo._visible=true;
					_root.yahoo._alpha=alpha;	
					_root.yahoo._x=0; _root.yahoo._y=0;
					_root.ylat=centrelat(_root.bgyoffset);
					_root.ylon=centrelong(_root.bgxoffset);
					_root.yzoom=18-_root.scale;
					_root.map.tiles._visible=false;
					if     (!_root.yahooloaded) { loadMovie(yahoourl,_root.yahoo);
												  _root.yahooloaded=true;
												  _root.yahoo.swapDepths(_root.masksquare); }
					else if (_root.yahooinited) { repositionYahoo(true); }
					break;

			default: // Tiles
					if (_root.tilesetloaded!=preferences.data.tilecustom+'/'+preferences.data.bgtype+'/'+preferences.data.tileset) {
						_root.tilesetloaded=preferences.data.tilecustom+'/'+preferences.data.bgtype+'/'+preferences.data.tileset;
						initTiles();
					}
					_root.map.tiles._visible=true;
					_root.map.tiles._alpha=alpha;
					_root.yahoo._visible=false;
					updateTiles();
					break;
		}
	}

	function repositionYahoo(force) {
		clearInterval(_root.yahooresizer);
		if (!_root.yahooinited) { return; }
		var ppos=_root.yahoo.myMap.getCenter();
		if (ppos) {
			ppos.lat=_root.ylat;
			ppos.lon=_root.ylon;
			if (_root.lastyzoom!=_root.yzoom) {
				_root.yahoo.myMap.setCenterByLatLonAndZoom(ppos,_root.yzoom,0);
			} else if (_root.lastylat!=_root.ylat || _root.lastylon!=_root.ylon || force) {
				_root.yahoo.myMap.setCenterByLatLon(ppos,0);
			}
			clearInterval(_root.copyrightID);
			_root.copyrightID=setInterval(refreshYahooCopyright,1000);
			_root.lastyzoom=_root.yzoom;
			_root.lastylon =_root.ylon;
			_root.lastylat =_root.ylat;
		}
	}

	function refreshYahooCopyright() {
		clearInterval(_root.copyrightID);
		_root.yahoo.myMap.map.updateCopyright();
	};

	function enableYahooZoom() {
		b=_global.com.yahoo.maps.projections.Projection.prototype;
		ASSetPropFlags(b,null,0,true);
		b.MAXLEVEL=20;
	
		b=_global.com.yahoo.maps.projections.MercatorProjection.prototype;
		ASSetPropFlags(b,null,0,true);
	
		b.ll_to_pxy = function (lat, lon) {
			var ys=18-_root.scale;
			var cp=1 << 26 - ys;
			this.level_=ys;
			this.ntiles_w_ = cp / this.tile_w_;
			this.ntiles_h_ = cp / this.tile_h_;
			this.meters_per_pixel_ = 111111*360 / cp;
			this.x_per_lon_ = cp / 360;
			
			alat = Math.abs(lat);
			alon = lon + 180;
			v_pxy = new this.PixelXY();
			if (alat >= 90 || alon > 360 || alon < 0) {
				return v_pxy;
			}
			alat *= this.RAD_PER_DEG;
			v_pxy.m_x = alon * this.x_per_lon_;
			ytemp = Math.log(Math.tan(alat) + 1 / Math.cos(alat)) / Math.PI;
			v_pxy.m_y = ytemp * this.pixel_height() / 2;
			if (lat < 0) {
				v_pxy.m_y = -v_pxy.m_y;
			}
			this.status_ = 1;
			return v_pxy;
		};
	
		b=_global.com.yahoo.maps.flash.ExtensibleTileUrl.prototype;
		ASSetPropFlags(b,null,0,true);
	
		b.makeUrl = function (row, col, mapViewType) {
		  return this.satelliteUrl + '&x=' + col + '&y=' + row + '&z=' + String(19-this.zoom) + '&r=1&v=' + this.satelliteBatch + '&t=a';
		};
	}
