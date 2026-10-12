# 1. Introduction of Efficient Methods

This is a final paper that describes a very efficient framework.
As shown by Li et al. in [our paper Fig. 1. Detailed comparison is given.](http://example.com/fig1), the results are promising.

Es gibt viele Anwendungen, z. B. in der Informatik.
Eine weitere Anwendung ist in der Medizin.

We also use the formula $x_{i}+y_{j}$, where $x$ and $y$ are variables.
The cost is \$$b$ per unit, and we satisfy $b\$$ boundary.

- The first objective is to design a high-performance classifier, which runs in real-time on embedded platforms.
  - Specifically, we target devices with less than 2GB of RAM.

> # Heading inside blockquote
> - item one in quote with a continuation line
> - item two

## 2. German Academic Context

The authors would like to thank Dipl.-Ing. A. Stadermann for technical support.

Here we propose architectures with readout circuits for both, the phase resp. time-of-flight values and the pixel intensities.

With the optical input signal $s(t)$ of modulation amplitude and phase $\varphi, $, and the demodulation signal $g(t)$ defined as follows.

The sampling function, a $\mathrm{rect}(t/\Delta t)$ function, where $\Delta t$ is the integration time.

The micro-photograph gives an overview of a the PMD-chip, including readout circuitry.

## 3. Image Splitting Sentence

The key components for RFMI-measurement are the

![image](https://example.com/fig1.jpg)

Fig. 1 Scheme of a PMD-array applied in the 3D-imaging system.

2D-mixer and the 2D-detector.

A transfer characteristic should be described analogously to conventional electro-optic

![image](https://example.com/fig2.jpg)

Fig. 8 Cross-sectional view of the device.

modulators (EOMs), e.g., Pockels cells.

## 4. Tables and Code

| 参数名 | 类型 | 描述 |
| --- | --- | --- |
| outFrame | frame | 输出图像,即 |
| exposureTime | uint32_t | 曝光时间[0x0, 0x3ff] |

| 引擎 | 说明 |
| --- | --- |
| AE 引擎 | 自动曝光,基于 Statistics |

```c
typedef struct {
    uint32_t enable;
} XcamAeManual;

XcamReturn rkAiqExpParamComb(const XcamParamComb_t *combp);

```

```txt
4.1.1 XcamAeStats_t
```

The AE engine computes exposure from statistics.
