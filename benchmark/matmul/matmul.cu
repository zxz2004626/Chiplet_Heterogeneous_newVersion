#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <sys/time.h>
#include <stdio.h>
#include <math.h>
#include <string>
#include <iostream>
#include <fstream>

/**
 * 本示例程序为：通过4个GPU chiplet
 * 计算随机数矩阵A（400 * 100）与随机数矩阵B（100 * 400）相乘结果。
 * 由矩阵乘法原理可知，我们可将计算任务划分为4个100*100的矩阵相乘，并将结果相加。
 */

#define Row 100
#define Col 100

/**
 * 矩阵乘法的核心函数，由每个线程都会运行一次本函数，
 * 根据线程编号不同计算出位于结果矩阵不同位置的数据。
 */

__global__ void matrix_mul_gpu(int *M, int* N, int* P, int width)
{
	int sumNum = threadIdx.x + threadIdx.y*10 ;
	int i = threadIdx.x;
	int j = threadIdx.y;
	int sum = 0;
	for(int k=0;k<width;k++)
	{
		int a = M[j*width+k];
		int b = N[k*width+i];
		sum += a*b;
	}
	P[sumNum] = sum;
}

/**
 * 用于传递单个chiplet计算结果的kernel函数
 */
__global__ void passMessage(int dstX, int dstY, int srcX,int srcY,int* data, int dataSize){
	int para1 = srcX *10000000 + srcY*100000 + dstX*1000+dstY * 10 ;
	for(int i = 0; i<dataSize;i++){
		asm("addc.s32 %0, %1, %2;" : "=r"(data[i]) : "r"(para1) , "r"(data[i]));
	}
}

__global__ void readMessage(int dstX, int dstY, int srcX,int srcY,int* data, int dataSize)
{
	int para1 = srcX *10000000 + srcY*100000 + dstX*1000+dstY * 10 + 1 ;
	for(int i = 0; i<dataSize;i++){
		data[i]=i;
		asm("addc.s32 %0, %1, %2;" : "=r"(data[i]) : "r"(para1) , "r"(data[i]));
	}
}

int main(int argc, char** argv)
{
	//读取本进程所代表的chiplet编号

	int srcX=atoi(argv[1]);
	int srcY=atoi(argv[2]);
	int *d_dataA, *d_dataB, *d_dataC;
	cudaMalloc((void**)&d_dataA, sizeof(int) *Row*Col);
	cudaMalloc((void**)&d_dataB, sizeof(int) *Row*Col);
	cudaMalloc((void**)&d_dataC, sizeof(int) *Col);

	readMessage <<<1,1>>> (0,0,srcX,srcY,d_dataA,10000);
	readMessage <<<1,1>>> (0,0,srcX,srcY,d_dataB,10000);

	//calculate
	dim3 threadPerBlock(10,10);
	dim3 blockNumber(1);
	matrix_mul_gpu << <blockNumber, threadPerBlock >> > (d_dataA, d_dataB, d_dataC, Col);

	passMessage << <1,1>> > (srcX,srcY,0,0,d_dataC,100);
	cudaFree(d_dataA);
	cudaFree(d_dataB);
	cudaFree(d_dataC);
	return 0;
}