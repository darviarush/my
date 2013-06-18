<?php

class BannerPath {
	public $id, $ext;

	function __construct($id, $ext) {
		$this->id = $id;
		$this->ext = $ext;
	}

	function path() {
		$id = $this->id;
		$len = strlen($id);
		$first = $id[$len - 1];
		$second = $id[$len - 2];
		if($second === "") { $id = "0$id"; $second = "0"; }
		return "../banners/$first/$second/$id.".$this->ext;
	}

	function create_path() {
		$path = $this->path();
		if(!file_exists($path)) {
			$dir2 = dirname($path);
			$dir1 = dirname($dir2);
			@mkdir($dir1);
			@mkdir($dir2);
		}
		return $path;
	}

	function url() {
		return sprintf("%s/banner/%%u/%02d.%s", Yii::app()->getRequest()->getHostInfo(''), $this->id, $this->ext);
	}

	function delete() {
		$path = $this->path();
		$dir1 = dirname($path);
		@unlink($path);
		@rmdir($dir1);
		@rmdir(dirname($dir1));
	}

	function preview() {
		$uri = substr($this->path(), 2);
		if($this->ext == 'swf') return $this->swf($uri);
		return $this->img($uri);
	}

	function href($content) {
		# Yii::app()->getRequest()->getHostInfo('')
		return sprintf('<a href="%s/catalog-%%p/?ref_id=%%u&bid=%d">%s</a>', "http://220.devnwth.tk", $this->id, $content);
	}

	function img($url) {
		return "<img src='$url'>";
	}

	function swf($url) {
		return '<object type="application/x-shockwave-flash" data="'.$url.'" width="200" height="150">'."\n".'</object>';
	}
}
